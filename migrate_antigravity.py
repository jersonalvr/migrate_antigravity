import os
import shutil
import sqlite3
import base64
import time
import subprocess

def parse_repeated_protobuf(val):
    entries = {}
    idx = 0
    while idx < len(val):
        start = idx
        tag = val[idx]
        if tag == 10:  # field 1, length-delimited
            idx += 1
            length = 0
            shift = 0
            while True:
                b = val[idx]
                length |= (b & 0x7f) << shift
                idx += 1
                if not (b & 0x80):
                    break
                shift += 7
            
            end = idx + length
            block_bytes = val[start:end]
            
            # Extract key to deduplicate
            child_idx = idx - start
            child_tag = block_bytes[child_idx]
            if child_tag == 10:
                child_idx += 1
                child_len = block_bytes[child_idx]
                child_idx += 1
                key = block_bytes[child_idx:child_idx+child_len].decode('utf-8', errors='ignore')
                entries[key] = block_bytes
            idx = end
        else:
            break
    return entries

def is_ide_running():
    try:
        output = subprocess.check_output('tasklist', shell=True).decode('utf-8', errors='ignore')
        return 'Antigravity IDE.exe' in output
    except Exception:
        return False

def migrate():
    # Dynamically determine the user's home directory and AppData paths
    home = os.path.expanduser('~')
    appdata = os.environ.get('APPDATA', os.path.join(home, 'AppData', 'Roaming'))
    
    old_db_path = os.path.join(appdata, 'Antigravity', 'User', 'globalStorage', 'state.vscdb')
    new_db_path = os.path.join(appdata, 'Antigravity IDE', 'User', 'globalStorage', 'state.vscdb')
    
    print("Waiting for Antigravity IDE to close...")
    while is_ide_running():
        time.sleep(1)
    
    print("Antigravity IDE closed! Waiting 2 seconds for locks to release...")
    time.sleep(2)
    
    print("Step 1: Merging globalState keys in state.vscdb...")
    if not os.path.exists(old_db_path):
        print(f"Error: Old state.vscdb not found at {old_db_path}")
        return
        
    if not os.path.exists(new_db_path):
        print(f"Error: New state.vscdb not found at {new_db_path}")
        return

    # Backup new DB
    shutil.copy2(new_db_path, new_db_path + ".bak")
    print(f"Backed up new state.vscdb to: {new_db_path}.bak")
    
    # Connect and process
    conn_old = sqlite3.connect(old_db_path)
    cur_old = conn_old.cursor()
    
    conn_new = sqlite3.connect(new_db_path)
    cur_new = conn_new.cursor()
    
    keys_to_merge = [
        'antigravityUnifiedStateSync.trajectorySummaries',
        'antigravityUnifiedStateSync.sidebarWorkspaces'
    ]
    
    for key in keys_to_merge:
        print(f"Merging key '{key}'...")
        cur_old.execute("SELECT value FROM ItemTable WHERE key = ?", (key,))
        row_old = cur_old.fetchone()
        
        cur_new.execute("SELECT value FROM ItemTable WHERE key = ?", (key,))
        row_new = cur_new.fetchone()
        
        old_val = base64.b64decode(row_old[0]) if row_old else b''
        new_val = base64.b64decode(row_new[0]) if row_new else b''
        
        old_entries = parse_repeated_protobuf(old_val)
        new_entries = parse_repeated_protobuf(new_val)
        
        merged_entries = {}
        merged_entries.update(old_entries)
        merged_entries.update(new_entries)
        
        merged_bytes = b''.join(merged_entries.values())
        merged_b64 = base64.b64encode(merged_bytes).decode('utf-8')
        
        cur_new.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)", (key, merged_b64))
        print(f"  Merged {len(old_entries)} old and {len(new_entries)} new -> {len(merged_entries)} entries.")
        
    conn_new.commit()
    conn_new.close()
    conn_old.close()
    print("Database merge completed successfully!")
    
    # Step 2: Copying missing .pb files
    print("\nStep 2: Copying missing .pb conversation files...")
    old_conv_dir = os.path.join(home, ".gemini", "antigravity", "conversations")
    new_conv_dir = os.path.join(home, ".gemini", "antigravity-ide", "conversations")
    
    if os.path.exists(old_conv_dir) and os.path.exists(new_conv_dir):
        copied_pb = 0
        for f in os.listdir(old_conv_dir):
            if f.endswith('.pb'):
                src = os.path.join(old_conv_dir, f)
                dst = os.path.join(new_conv_dir, f)
                if not os.path.exists(dst):
                    shutil.copy2(src, dst)
                    copied_pb += 1
        print(f"Copied {copied_pb} missing .pb files.")
        
    # Step 3: Copying missing brain subdirectories
    print("\nStep 3: Copying missing brain subdirectories...")
    old_brain_dir = os.path.join(home, ".gemini", "antigravity", "brain")
    new_brain_dir = os.path.join(home, ".gemini", "antigravity-ide", "brain")
    
    if os.path.exists(old_brain_dir) and os.path.exists(new_brain_dir):
        copied_brain = 0
        for d in os.listdir(old_brain_dir):
            src_dir = os.path.join(old_brain_dir, d)
            if os.path.isdir(src_dir):
                dst_dir = os.path.join(new_brain_dir, d)
                if not os.path.exists(dst_dir):
                    shutil.copytree(src_dir, dst_dir)
                    copied_brain += 1
        print(f"Copied {copied_brain} missing brain directories.")
        
    print("\nALL MIGRATION STEPS SUCCESSFUL!")
    
    # Write a status file in scratch to verify completion
    status_file = os.path.join(home, ".gemini", "antigravity-ide", "scratch", "migration_done.txt")
    with open(status_file, "w") as sf:
        sf.write("SUCCESS")
    print(f"Status file written to: {status_file}")

if __name__ == '__main__':
    migrate()
