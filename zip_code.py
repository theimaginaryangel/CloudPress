import os
import zipfile

def create_zip(source_dir, output_filename):
    with zipfile.ZipFile(output_filename, 'w', zipfile.ZIP_DEFLATED) as zipf:
        for root, _, files in os.walk(source_dir):
            for file in files:
                file_path = os.path.join(root, file)
                # Ensure we don't include terraform state or huge dirs
                if '.terraform' in file_path or '.tfstate' in file_path:
                    continue
                # Calculate relative path
                arcname = os.path.relpath(file_path, source_dir)
                # Convert backslashes to forward slashes for Linux compatibility
                arcname = arcname.replace('\\', '/')
                zipf.write(file_path, arcname)

create_zip('staging', 'source.zip')
