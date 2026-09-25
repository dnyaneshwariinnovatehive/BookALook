const fs = require('fs');
const path = require('path');

function walk(dir) {
    let results = [];
    const list = fs.readdirSync(dir);
    list.forEach(function(file) {
        file = path.join(dir, file);
        const stat = fs.statSync(file);
        if (stat && stat.isDirectory()) {
            results = results.concat(walk(file));
        } else {
            if (file.endsWith('.dart')) {
                results.push(file);
            }
        }
    });
    return results;
}

const files = walk('Partner App/lib/screens');

files.forEach(file => {
    let content = fs.readFileSync(file, 'utf8');
    
    // Replace color: Colors.black87 -> color: Theme.of(context).colorScheme.onSurface
    content = content.replace(/color:\s*Colors\.black87/g, 'color: Theme.of(context).colorScheme.onSurface');
    // Replace color: Colors.black54 -> color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)
    content = content.replace(/color:\s*Colors\.black54/g, 'color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)');
    
    fs.writeFileSync(file, content, 'utf8');
});
console.log('Done replacing camouflage colors.');
