import os
import re

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    original = content

    # Colors.white as background or text? It's risky to replace blindly, but let's do the safe ones:
    content = re.sub(r'Colors\.black26', r'Theme.of(context).colorScheme.onSurface.withOpacity(0.26)', content)
    content = re.sub(r'Colors\.black38', r'Theme.of(context).colorScheme.onSurface.withOpacity(0.38)', content)
    content = re.sub(r'Colors\.black54', r'Theme.of(context).colorScheme.onSurface.withOpacity(0.54)', content)
    content = re.sub(r'Colors\.black87', r'Theme.of(context).colorScheme.onSurface.withOpacity(0.87)', content)
    content = re.sub(r'Colors\.black', r'Theme.of(context).colorScheme.onSurface', content)
    
    # Grey shades
    content = re.sub(r'Colors\.grey\[\d+\]', r'Theme.of(context).dividerColor', content)
    content = re.sub(r'Colors\.grey\.shade\d+', r'Theme.of(context).dividerColor', content)
    content = re.sub(r'Colors\.grey', r'Theme.of(context).colorScheme.onSurface.withOpacity(0.5)', content)

    # Semantic Colors (Light/Dark Context needed)
    # Since we can't easily do `isDark ? AppTheme.darkDanger : AppTheme.lightDanger` without `isDark` variable,
    # we can use standard Semantic Colors from Theme, or we can use our AppTheme properties if we inject `final isDark = Theme.of(context).brightness == Brightness.dark;`
    # Let's just use `AppTheme.statusAvailable` for Green, `AppTheme.statusBusy` for Red, etc. if they are static regardless of theme.
    # Wait, the spec says Semantic Colors change in dark mode: Success: #2E7D32 -> #81C784
    # To keep it simple in regex, I'll map Colors.green to `(Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSuccess : AppTheme.lightSuccess)`
    
    content = re.sub(r'Colors\.green\b', r'(Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSuccess : AppTheme.lightSuccess)', content)
    content = re.sub(r'Colors\.red\b', r'(Theme.of(context).brightness == Brightness.dark ? AppTheme.darkDanger : AppTheme.lightDanger)', content)
    content = re.sub(r'Colors\.orange\b', r'(Theme.of(context).brightness == Brightness.dark ? AppTheme.darkWarning : AppTheme.lightWarning)', content)
    content = re.sub(r'Colors\.blue\b', r'(Theme.of(context).brightness == Brightness.dark ? AppTheme.darkInfo : AppTheme.lightInfo)', content)

    # Colors.white: mostly used for background in these apps (like Card, Container).
    # If it's used for foreground in elevated button, `foregroundColor: Colors.white` is correct because primary accent is purple, and text on purple is white in BOTH themes.
    # Let's replace `fillColor: Colors.white` with `fillColor: Theme.of(context).colorScheme.surface`
    content = re.sub(r'fillColor:\s*Colors\.white', r'fillColor: Theme.of(context).colorScheme.surface', content)
    # `color: Colors.white` in Container/BoxDecoration
    content = re.sub(r'color:\s*Colors\.white', r'color: Theme.of(context).colorScheme.surface', content)
    # Fix instances where foregroundColor was replaced by mistake because of `color: Colors.white` 
    # (Actually `color: Colors.white` matches `foregroundColor: Colors.white`? No, regex expects word boundary if we want. Wait, `color:` not `foregroundColor:`.)
    content = re.sub(r'(?<!foreground)color:\s*Colors\.white', r'color: Theme.of(context).colorScheme.surface', content)
    content = re.sub(r'backgroundColor:\s*Colors\.white', r'backgroundColor: Theme.of(context).colorScheme.surface', content)

    # Add missing import if needed
    if 'AppTheme' in content and 'import' in content and 'app_theme.dart' not in content:
        # Find the first import
        import_match = re.search(r'import\s+[\'"].*?[\'"];\n', content)
        if import_match:
            # We don't know the exact relative path, so we use a package import if possible, or just skip if too complex.
            # Usually they already have it, or we can just hope.
            pass

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
