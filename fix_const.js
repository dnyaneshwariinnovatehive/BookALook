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
    
    // Replace const IconThemeData(color: Theme.of(context) -> IconThemeData(color: Theme.of(context)
    content = content.replace(/const\s+IconThemeData\(color:\s*Theme\.of\(context\)/g, 'IconThemeData(color: Theme.of(context)');
    // Just in case, replace const Text with a style containing Theme.of(context)
    content = content.replace(/const\s+Text\(([^)]*Theme\.of\(context\)[^)]*)\)/g, 'Text($1)');
    
    fs.writeFileSync(file, content, 'utf8');
});
console.log('Done fixing const issues.');
