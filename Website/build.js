const fs = require('fs');
const path = require('path');
const { marked } = require('marked');

// Ensure dist directories exist
const distDirs = ['dist', 'dist/docs', 'dist/docs/guide', 'dist/docs/reference'];
distDirs.forEach(dir => {
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
    }
});

// Read head partial
const headPartial = fs.readFileSync('src/partials/head.html', 'utf8');

// Process HTML file with head partial injection
function processHtmlFile(srcPath, destPath, stylesheetPath = 'style.css') {
    if (!fs.existsSync(srcPath)) return;

    let content = fs.readFileSync(srcPath, 'utf8');

    // Replace {{head}} placeholder with head partial content
    const headContent = headPartial.replace('{{stylesheet}}', stylesheetPath);
    content = content.replace('{{head}}', headContent);

    fs.writeFileSync(destPath, content);
}

// Process main HTML files (stylesheet at same level)
const mainHtmlFiles = ['index.html', 'fdd.html', 'docs.html', 'getting-started.html', 'disclaimer.html'];
mainHtmlFiles.forEach(file => {
    processHtmlFile(`src/${file}`, `dist/${file}`, 'style.css');
});

// Process doc-template.html (stylesheet at parent level)
processHtmlFile('src/doc-template.html', 'dist/doc-template.html', '../style.css');

// Process docs subdirectory pages
const docsSubPages = ['event-driven.html', 'state-transitions.html', 'data-pipelines.html', 'native-compilation.html', 'language-proposals.html'];
docsSubPages.forEach(file => {
    processHtmlFile(`src/docs/${file}`, `dist/docs/${file}`, '../style.css');
});

// Copy style.css
if (fs.existsSync('src/style.css')) {
    fs.copyFileSync('src/style.css', 'dist/style.css');
}

// Read template for markdown docs (1 level deep: /docs/)
const docTemplate = fs.readFileSync('src/doc-template.html', 'utf8');
const docHeadContent = headPartial.replace('{{stylesheet}}', '../style.css');
const processedDocTemplate = docTemplate.replace('{{head}}', docHeadContent);

// Template for nested pages (2 levels deep: /docs/guide/, /docs/reference/)
const nestedDocTemplate = fs.readFileSync('src/doc-template-nested.html', 'utf8');
const nestedHeadContent = headPartial.replace('{{stylesheet}}', '../../style.css');
const processedNestedTemplate = nestedDocTemplate.replace('{{head}}', nestedHeadContent);

// Extract title from markdown content
function extractTitle(markdown) {
    const match = markdown.match(/^#\s+(.+)$/m);
    return match ? match[1] : 'Documentation';
}

// Process a markdown file to HTML
function processMarkdownFile(srcPath, destPath, template) {
    if (!fs.existsSync(srcPath)) return null;

    const md = fs.readFileSync(srcPath, 'utf8');
    const title = extractTitle(md);
    const html = marked.parse(md);
    const page = template
        .replace('{{content}}', html)
        .replace('{{title}}', title);

    fs.writeFileSync(destPath, page);
    return { title, srcPath, destPath };
}

// Documentation directory
const docsDir = '../Documentation';

// Process top-level documentation files
const topLevelDocs = [
    { src: 'GettingStarted.md', dest: 'getting-started.html' },
    { src: 'StartWithARO.md', dest: 'start-with-aro.html' },
    { src: 'LanguageTour.md', dest: 'language-tour.html' },
    { src: 'ActionDeveloperGuide.md', dest: 'action-developer-guide.html' },
    { src: 'README.md', dest: 'index.html' }
];

console.log('Processing top-level documentation...');
topLevelDocs.forEach(doc => {
    const srcPath = `${docsDir}/${doc.src}`;
    const destPath = `dist/docs/${doc.dest}`;
    if (fs.existsSync(srcPath)) {
        const result = processMarkdownFile(srcPath, destPath, processedDocTemplate);
        if (result) {
            console.log(`  - ${doc.src} -> ${doc.dest}`);
        }
    }
});

// Process LanguageGuide files
const languageGuideDir = `${docsDir}/LanguageGuide`;
if (fs.existsSync(languageGuideDir)) {
    console.log('Processing LanguageGuide...');
    const guideFiles = fs.readdirSync(languageGuideDir).filter(f => f.endsWith('.md'));

    guideFiles.forEach(file => {
        const srcPath = `${languageGuideDir}/${file}`;
        const destFile = file.replace('.md', '.html').toLowerCase().replace(/\s+/g, '-');
        const destPath = `dist/docs/guide/${destFile}`;

        const result = processMarkdownFile(srcPath, destPath, processedNestedTemplate);
        if (result) {
            console.log(`  - LanguageGuide/${file} -> guide/${destFile}`);
        }
    });
}

// Process LanguageReference files
const languageRefDir = `${docsDir}/LanguageReference`;
if (fs.existsSync(languageRefDir)) {
    console.log('Processing LanguageReference...');
    const refFiles = fs.readdirSync(languageRefDir).filter(f => f.endsWith('.md'));

    refFiles.forEach(file => {
        const srcPath = `${languageRefDir}/${file}`;
        const destFile = file.replace('.md', '.html').toLowerCase().replace(/\s+/g, '-');
        const destPath = `dist/docs/reference/${destFile}`;

        const result = processMarkdownFile(srcPath, destPath, processedNestedTemplate);
        if (result) {
            console.log(`  - LanguageReference/${file} -> reference/${destFile}`);
        }
    });
}

console.log('Build complete! Files written to dist/');
