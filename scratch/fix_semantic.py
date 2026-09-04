import os
import re

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original = content

    # Info
    content = re.sub(r'#eff6ff\b|#e0f2fe\b', r'var(--color-info-bg)', content)
    content = re.sub(r'#3b82f6\b|#2563eb\b|#0284c7\b|#0369a1\b|#0ea5e9\b', r'var(--color-info)', content)

    # Success
    content = re.sub(r'#f0fdf4\b|#dcfce7\b', r'var(--color-success-bg)', content)
    content = re.sub(r'#22c55e\b|#16a34a\b|#15803d\b', r'var(--color-success)', content)

    # Accent (Purple)
    content = re.sub(r'#faf5ff\b|#f3e8ff\b', r'var(--accent-soft)', content)
    content = re.sub(r'#a855f7\b|#9333ea\b|#7e22ce\b', r'var(--accent-color)', content)

    # Warning (Orange)
    content = re.sub(r'#fff7ed\b|#ffedd5\b|#fef3c7\b', r'var(--color-warning-bg)', content)
    content = re.sub(r'#f97316\b|#ea580c\b|#f59e0b\b|#d97706\b', r'var(--color-warning)', content)

    # Danger (Red)
    content = re.sub(r'#fef2f2\b|#fee2e2\b|#fca5a5\b', r'var(--color-danger-bg)', content)
    content = re.sub(r'#ef4444\b|#dc2626\b|#b91c1c\b', r'var(--color-danger)', content)

    # Random Gradients with Tailwind colors
    content = re.sub(r'linear-gradient\([^)]+#2563eb[^)]+#38bdf8[^)]+\)', r'var(--accent-gradient)', content)
    content = re.sub(r'#38bdf8\b', r'var(--accent-color)', content)

    if content != original:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        return True
    return False

def process_directory(directory):
    count = 0
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.module.css'):
                if process_file(os.path.join(root, file)):
                    count += 1
    print(f"Updated {count} files in {directory}")

process_directory('d:/BookALook/website/src/app')
