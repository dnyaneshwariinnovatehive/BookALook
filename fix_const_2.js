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
    
    // Replace const BoxDecoration(color: Theme.of(context) -> BoxDecoration(color: Theme.of(context)
    content = content.replace(/const\s+BoxDecoration\([^)]*Theme\.of\(context\)[^)]*\)/g, match => match.replace(/^const\s+/, ''));
    // Replace const Icon(..., color: Theme.of(context) -> Icon(..., color: Theme.of(context)
    content = content.replace(/const\s+Icon\([^)]*Theme\.of\(context\)[^)]*\)/g, match => match.replace(/^const\s+/, ''));
    
    fs.writeFileSync(file, content, 'utf8');
});
console.log('Done fixing more const issues.');
