import os
import re

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    original = content

    # 1. Fix onSurface12 -> onSurface.withValues(alpha: 0.12)
    content = content.replace('Theme.of(context).colorScheme.onSurface12', 'Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12)')

    # 2. Add AppTheme import if missing
    if 'AppTheme.' in content:
        import_stmt_partner = "import 'package:partner_app/theme/app_theme.dart';"
        import_stmt_customer = "import 'package:customer_app/theme/app_theme.dart';"
        
        if 'partner_app' in filepath.replace('\\', '/') or 'Partner App' in filepath:
            if import_stmt_partner not in content:
                content = import_stmt_partner + "\n" + content
        elif 'customer_app' in filepath.replace('\\', '/') or 'Customer App' in filepath:
            if import_stmt_customer not in content:
                content = import_stmt_customer + "\n" + content

    # 3. Strip more consts using regex (across newlines)
    # This regex looks for `const ` followed by whitespace/newlines and then the class name
    content = re.sub(r'\bconst\s+(Text\()', r'\1', content)
    content = re.sub(r'\bconst\s+(TextStyle\()', r'\1', content)
    content = re.sub(r'\bconst\s+(Icon\()', r'\1', content)
    content = re.sub(r'\bconst\s+(Divider\()', r'\1', content)
    content = re.sub(r'\bconst\s+(InputDecoration\()', r'\1', content)
    
    # Wait, stripping `const Text` everywhere might cause other linter warnings (prefer_const_constructors), 
    # but it will fix the compilation errors unconditionally. Since the user just wants the compile errors gone 
    # and the linter can be fixed later, this is the safest and fastest way.

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
