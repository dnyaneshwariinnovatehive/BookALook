import os
import re

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    original = content

    # Replace `.shade100` and `.shade50` since we don't have shades in the semantic colors.
    content = re.sub(r'AppTheme\.lightSuccess\)\.shade100', r'AppTheme.lightSuccess).withValues(alpha: 0.1)', content)
    content = re.sub(r'AppTheme\.darkSuccess\)\.shade100', r'AppTheme.darkSuccess).withValues(alpha: 0.1)', content)
    
    content = re.sub(r'AppTheme\.lightDanger\)\.shade100', r'AppTheme.lightDanger).withValues(alpha: 0.1)', content)
    content = re.sub(r'AppTheme\.darkDanger\)\.shade100', r'AppTheme.darkDanger).withValues(alpha: 0.1)', content)

    content = re.sub(r'AppTheme\.lightWarning\)\.shade50', r'AppTheme.lightWarning).withValues(alpha: 0.05)', content)
    content = re.sub(r'AppTheme\.darkWarning\)\.shade50', r'AppTheme.darkWarning).withValues(alpha: 0.05)', content)
    
    content = re.sub(r'AppTheme\.lightDanger\)\[50\]', r'AppTheme.lightDanger).withValues(alpha: 0.05)', content)
    content = re.sub(r'AppTheme\.darkDanger\)\[50\]', r'AppTheme.darkDanger).withValues(alpha: 0.05)', content)

    # We also need to add missing AppTheme imports.
    if 'AppTheme.' in content and 'import \'package:partner_app/theme/app_theme.dart\';' not in content and 'import \'package:customer_app/theme/app_theme.dart\';' not in content:
        # Determine if partner or customer
        if 'partner_app' in filepath.replace('\\', '/'):
            content = "import 'package:partner_app/theme/app_theme.dart';\n" + content
        elif 'Customer App' in filepath:
            content = "import 'package:customer_app/theme/app_theme.dart';\n" + content

    # Fixing const issues:
    # A simple but effective way is to look for `const ` followed by `Text`, `TextStyle`, `Icon`, `Divider`
    # and if the block of text nearby (say next 200 chars) contains `Theme.of`, we drop `const`.
    # Actually, we can just remove `const ` if it appears on the same line as `Theme.of(context)` or `AppTheme.`
    lines = content.split('\n')
    for i in range(len(lines)):
        # If the line has 'Theme.of(context)' or 'AppTheme'
        if 'Theme.of(context)' in lines[i] or 'AppTheme.' in lines[i]:
            # Remove const from this line
            lines[i] = re.sub(r'\bconst\s+(Text|TextStyle|Icon|Divider|InputDecoration)\b', r'\1', lines[i])
            
            # Sometimes the const is on the previous line. Let's check previous 1-2 lines.
            if i > 0 and 'const ' in lines[i-1] and not ('Theme.of' in lines[i-1] or 'AppTheme.' in lines[i-1]):
                 # if the previous line ended by opening a widget that now has dynamic theme
                 if re.search(r'\bconst\s+(Text|TextStyle|Icon|Divider|InputDecoration)\(', lines[i-1]):
                     lines[i-1] = re.sub(r'\bconst\s+(Text|TextStyle|Icon|Divider|InputDecoration)\b', r'\1', lines[i-1])

            if i > 1 and 'const ' in lines[i-2] and not ('Theme.of' in lines[i-2] or 'AppTheme.' in lines[i-2]):
                 if re.search(r'\bconst\s+(Text|TextStyle|Icon|Divider|InputDecoration)\(', lines[i-2]):
                     lines[i-2] = re.sub(r'\bconst\s+(Text|TextStyle|Icon|Divider|InputDecoration)\b', r'\1', lines[i-2])

    content = '\n'.join(lines)

    if content != original:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        return True
    return False

def process_directory(directory):
    count = 0
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.dart'):
                if process_file(os.path.join(root, file)):
                    count += 1
    print(f"Updated {count} files in {directory}")

process_directory('d:/BookALook/Partner App/lib')
process_directory('d:/BookALook/Customer App/lib')
