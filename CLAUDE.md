# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

공통 지침은 Codex와 함께 쓰는 `AGENTS.md`에서 관리한다. 내용은 그 파일에 추가하고, 이 파일에는 Claude 전용 내용만 둔다.

@AGENTS.md

## 서브에이전트 사용
- 코드 점검(버그, 규칙 위반, 성능 개선)은 `code-inspector` 서브에이전트에게 맡긴다. 기능 구현이나 수정이 끝나면 점검을 요청받지 않아도 `code-inspector`로 점검한다.
- `code-inspector`가 보고한 버그와 규칙 위반은 사용자에게 알리고, 수정은 사용자가 요청할 때 진행한다.
- 버그 수정, 문제 해결, 속도·효율 개선은 `code-fixer` 서브에이전트에게 맡긴다. `code-inspector` 보고서를 바탕으로 수정할 때는 보고서 내용을 그대로 `code-fixer`에게 전달한다.
- `code-fixer`가 끝나면 그 처리 결과를 `code-inspector`에게 전달해 다시 점검한다.
- 화면·위젯의 디자인과 사용성 개선은 `design-improver` 서브에이전트에게 맡긴다. 디자인 작업이 끝나면 `code-inspector`로 점검한다.
- 화면이나 위젯이 새로 생기거나 바뀌는 구현은 다음 순서로 진행한다.
  1. 메인 Claude가 기능(상태·로직·API 연결)과 기본 화면을 구현한다.
  2. `design-improver`가 바뀐 화면의 디자인과 사용성을 다듬는다.
  3. `code-inspector`로 전체를 점검하고 결과를 보고한다.
- 화면 변경이 없는 구현(로직, API, 테스트만 바꾸는 경우)은 `design-improver`를 쓰지 않는다.
