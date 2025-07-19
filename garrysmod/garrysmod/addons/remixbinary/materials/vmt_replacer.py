#!/usr/bin/env python3
# vmt_replacer.py - Replaces "VertexLitGeneric" with "UnlitGeneric" in .vmt files

import os
import sys
import re

def find_vmt_files(folder_path):
    """Recursively find all .vmt files in the given folder and its subfolders."""
    vmt_files = []
    for root, dirs, files in os.walk(folder_path):
        for file in files:
            if file.lower().endswith('.vmt'):
                vmt_files.append(os.path.join(root, file))
    return vmt_files

def process_vmt_file(file_path):
    """Process a .vmt file to replace 'VertexLitGeneric' with 'UnlitGeneric' on the first line that contains it."""
    encodings = ['utf-8', 'latin-1', 'cp1252']  # Common encodings to try
    
    for encoding in encodings:
        try:
            # Read the file content
            with open(file_path, 'r', encoding=encoding) as file:
                lines = file.readlines()
            
            # Find the first line containing 'VertexLitGeneric' and replace it
            modified = False
            for i, line in enumerate(lines):
                if re.search(r'VertexLitGeneric', line, re.IGNORECASE):
                    # Replace 'VertexLitGeneric' with 'UnlitGeneric'
                    lines[i] = re.sub(r'VertexLitGeneric', 'UnlitGeneric', line, flags=re.IGNORECASE)
                    modified = True
                    break
            
            # Write the modified content back to the file if modified
            if modified:
                with open(file_path, 'w', encoding=encoding) as file:
                    file.writelines(lines)
                return True
            # File was read successfully but no replacement was needed
            return False
        except UnicodeDecodeError:
            # Try the next encoding
            continue
        except Exception as e:
            print(f"Error processing {file_path}: {e}")
            return False
    
    # If we get here, none of the encodings worked
    print(f"Could not process {file_path} due to encoding issues")
    return False

def main():
    # Check if a folder path was provided
    if len(sys.argv) < 2:
        print("Usage: python vmt_replacer.py <folder_path>")
        sys.exit(1)
    
    folder_path = sys.argv[1]
    
    # Validate the folder path
    if not os.path.isdir(folder_path):
        if os.path.isfile(folder_path) and folder_path.lower().endswith('.vmt'):
            # Single file mode
            if process_vmt_file(folder_path):
                print(f"Modified: {folder_path}")
            else:
                print(f"No changes made to: {folder_path}")
            return
        else:
            print(f"Invalid folder path: {folder_path}")
            sys.exit(1)
    
    # Find all .vmt files
    vmt_files = find_vmt_files(folder_path)
    
    if not vmt_files:
        print(f"No .vmt files found in {folder_path}")
        return
    
    # Process each file
    modified_count = 0
    for file_path in vmt_files:
        if process_vmt_file(file_path):
            modified_count += 1
            print(f"Modified: {file_path}")
    
    # Report results
    print(f"\nProcessed {len(vmt_files)} .vmt files, modified {modified_count} files.")

if __name__ == "__main__":
    main()