// PostToolUse 훅: 수정한 파일이 .dart 이면 dart format 을 실행한다.
const fs = require('fs');
const { spawnSync } = require('child_process');

let input = {};
try {
  input = JSON.parse(fs.readFileSync(0, 'utf8') || '{}');
} catch {
  process.exit(0);
}

const args = input.tool_input || {};
const file = args.file_path || (input.tool_response && input.tool_response.filePath) || '';

if (file.endsWith('.dart') && fs.existsSync(file)) {
  spawnSync('dart', ['format', file], { shell: true, stdio: 'ignore' });
}

process.exit(0);
