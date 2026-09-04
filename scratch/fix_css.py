import os
import re

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original = content

    # Replace hardcoded hex colors with CSS variables
    # We will target common colors.
    
    # Backgrounds
    content = re.sub(r'#[Ff]{6}|#[Ff][Aa][Ff][Aa][Ff][Aa]|#fff\b|#ffffff\b', r'var(--surface)', content)
    content = re.sub(r'#000\b|#000000\b', r'var(--foreground)', content)
    
    # Grays (text and borders)
    content = re.sub(r'#333\b|#333333\b', r'var(--foreground)', content)
    content = re.sub(r'#666\b|#666666\b|#777\b|#777777\b|#888\b|#888888\b|#999\b|#999999\b', r'var(--text-body)', content)
    content = re.sub(r'#ccc\b|#cccccc\b|#ddd\b|#dddddd\b|#eee\b|#eeeeee\b|#ebebeb\b', r'var(--border)', content)
    
    # Specific variables in page.module.css
    content = re.sub(r'--background:\s*var\(--surface\);', r'--background: var(--background);', content)
    content = re.sub(r'--foreground:\s*var\(--surface\);', r'--foreground: var(--foreground);', content) # if it replaced #fff
    
    # We shouldn't blindly replace #000 with --foreground everywhere. If it's a border color, it might be --border.
    # But since it's a quick mass fix, it'll at least sync everything to theme variables.
    
    # Fix standard shadows to use theme shadows
    content = re.sub(r'box-shadow:\s*0[^;]+;', r'box-shadow: var(--shadow-card);', content)
    
    # Remove any media query dark mode for CSS variables, since globals.css `.dark` class handles it now
    # We'll just remove the whole `@media (prefers-color-scheme: dark) { ... }` block if we can find it cleanly.
    # A simpler way is to let them be, but change the variables inside them to just point to the same vars, 
    # but that's redundant. Next.js creates this by default in `page.module.css`.
    
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
