#!/usr/bin/env python3
"""
Script to filter RTX config file to keep only texture-related settings.
Extracts all lines containing "Textures =" from the rtx.conf file.
"""

import os
import sys

def filter_texture_lines(input_file, output_file=None):
    """
    Filter lines from input_file that contain "Textures ="
    
    Args:
        input_file (str): Path to input rtx.conf file
        output_file (str, optional): Path to output file. If None, prints to stdout
    """
    
    if not os.path.exists(input_file):
        print(f"Error: Input file '{input_file}' not found!")
        return False
    
    texture_lines = []
    
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, 1):
                # Check if line contains "Textures ="
                if "Textures =" in line:
                    texture_lines.append(line.rstrip())
        
        # Output results
        if output_file:
            with open(output_file, 'w', encoding='utf-8') as f:
                for line in texture_lines:
                    f.write(line + '\n')
            print(f"Filtered {len(texture_lines)} texture lines to '{output_file}'")
        else:
            print(f"Found {len(texture_lines)} lines containing 'Textures =':\n")
            for line in texture_lines:
                print(line)
        
        return True
        
    except Exception as e:
        print(f"Error processing file: {e}")
        return False

def main():
    """Main function to handle command line arguments"""
    
    # Default input file
    input_file = "remix/rtx.conf"
    output_file = None
    
    # Parse command line arguments
    if len(sys.argv) > 1:
        input_file = sys.argv[1]
    
    if len(sys.argv) > 2:
        output_file = sys.argv[2]
    
    # Show usage if help requested
    if len(sys.argv) > 1 and sys.argv[1] in ['-h', '--help']:
        print("Usage: python filter_textures.py [input_file] [output_file]")
        print("  input_file: Path to rtx.conf file (default: remix/rtx.conf)")
        print("  output_file: Path to output file (default: print to stdout)")
        print("\nExample:")
        print("  python filter_textures.py remix/rtx.conf texture_settings.conf")
        return
    
    # Filter the texture lines
    success = filter_texture_lines(input_file, output_file)
    
    if not success:
        sys.exit(1)

if __name__ == "__main__":
    main() 