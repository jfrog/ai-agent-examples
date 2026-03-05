'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const SKILLS_DIR = path.join(__dirname, '..', 'skills');

const PLATFORM_API_SKILLS = new Set([
  'jfrog-artifactory',
  'jfrog-security',
  'jfrog-access',
  'jfrog-distribution',
  'jfrog-curation',
  'jfrog-apptrust',
  'jfrog-runtime',
  'jfrog-mission-control',
  'jfrog-workers',
  'jfrog-cli',
  'jfrog-patterns',
]);

function skillDirs() {
  return fs.readdirSync(SKILLS_DIR).filter(function (name) {
    const dir = path.join(SKILLS_DIR, name);
    return fs.statSync(dir).isDirectory() &&
           fs.existsSync(path.join(dir, 'SKILL.md'));
  });
}

function parseFrontmatter(content) {
  const match = content.match(/^---\n([\s\S]*?)\n---/);
  if (!match) return null;
  const pairs = {};
  for (const line of match[1].split('\n')) {
    const sep = line.indexOf(':');
    if (sep === -1) continue;
    pairs[line.slice(0, sep).trim()] = line.slice(sep + 1).trim();
  }
  return pairs;
}

function mdFiles(dir) {
  return fs.readdirSync(dir).filter(f => f.endsWith('.md'));
}

// ---------------------------------------------------------------------------
// Validate every skill directory
// ---------------------------------------------------------------------------

const skills = skillDirs();

describe('skill content validation', () => {
  for (const skill of skills) {
    const skillDir = path.join(SKILLS_DIR, skill);
    const isPlatformSkill = PLATFORM_API_SKILLS.has(skill);

    describe(skill, () => {
      it('contains SKILL.md', () => {
        assert.ok(
          fs.existsSync(path.join(skillDir, 'SKILL.md')),
          `${skill}/ must have a SKILL.md`
        );
      });

      it('SKILL.md has YAML frontmatter with name and description', () => {
        const content = fs.readFileSync(path.join(skillDir, 'SKILL.md'), 'utf8');
        const fm = parseFrontmatter(content);
        assert.ok(fm, `${skill}/SKILL.md must have YAML frontmatter (--- delimiters)`);
        assert.ok(fm.name, `${skill}/SKILL.md frontmatter must include "name"`);
        assert.ok(fm.description, `${skill}/SKILL.md frontmatter must include "description"`);
      });

      it('description mentions trigger keywords', { skip: !isPlatformSkill }, () => {
        const content = fs.readFileSync(path.join(skillDir, 'SKILL.md'), 'utf8');
        const fm = parseFrontmatter(content);
        assert.ok(fm && fm.description);
        assert.ok(
          /trigger/i.test(fm.description),
          `${skill}/SKILL.md description should mention trigger keywords`
        );
      });

      it('has an Authentication section', { skip: !isPlatformSkill }, () => {
        const content = fs.readFileSync(path.join(skillDir, 'SKILL.md'), 'utf8');
        assert.ok(
          /^##\s+.*auth/im.test(content),
          `${skill}/SKILL.md must have an Authentication heading`
        );
      });

      it('has a Documentation section with at least one URL', { skip: !isPlatformSkill }, () => {
        const content = fs.readFileSync(path.join(skillDir, 'SKILL.md'), 'utf8');
        const docMatch = content.match(/^##\s+.*[Dd]ocumentation[\s\S]*$/m);
        assert.ok(docMatch, `${skill}/SKILL.md must have a Documentation heading`);
        const docSection = content.slice(content.indexOf(docMatch[0]));
        assert.ok(
          /https?:\/\//.test(docSection),
          `${skill}/SKILL.md Documentation section must contain at least one URL`
        );
      });

      it('uses $JFROG_URL placeholder (no hardcoded JFrog hostnames)', () => {
        const ALLOWED = /^https?:\/\/(install-cli|releases|releases-ce)\.jfrog\.io/i;
        const EXAMPLE_NAMES = /^https?:\/\/(mycompany|myco|example|other|jpd\d*|server\d*|acme|site-[a-z]|your-[a-z-]+)\.jfrog\.io/i;

        const files = mdFiles(skillDir);
        for (const f of files) {
          const content = fs.readFileSync(path.join(skillDir, f), 'utf8');
          const matches = content.match(/https?:\/\/[a-z0-9-]+\.jfrog\.io\b/gi) || [];
          const violations = matches.filter(
            url => !ALLOWED.test(url) && !EXAMPLE_NAMES.test(url)
          );
          assert.equal(
            violations.length, 0,
            `${skill}/${f} should use $JFROG_URL instead of hardcoded hostnames: ${violations.join(', ')}`
          );
        }
      });

      it('all Markdown files are non-empty', () => {
        const files = mdFiles(skillDir);
        assert.ok(files.length > 0, `${skill}/ should have at least one .md file`);
        for (const f of files) {
          const content = fs.readFileSync(path.join(skillDir, f), 'utf8').trim();
          assert.ok(content.length > 0, `${skill}/${f} must not be empty`);
        }
      });

      it('supplementary files have .md extension', { skip: !isPlatformSkill }, () => {
        const allFiles = fs.readdirSync(skillDir);
        for (const f of allFiles) {
          const fullPath = path.join(skillDir, f);
          if (fs.statSync(fullPath).isFile()) {
            assert.ok(f.endsWith('.md'), `${skill}/${f} should be a .md file`);
          }
        }
      });
    });
  }
});
