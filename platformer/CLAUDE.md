# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

Godot 4.7 (Forward Plus, D3D12) 기반 2D 퍼즐 플랫포머. 어둠 속 실루엣 캐릭터가 색 보석(과일)을 먹어 색 상태를 얻고, 상태마다 이동 능력이 달라지는 게임이다. 인게임 맵 에디터를 함께 개발 중이다.

빌드/테스트/린트 도구는 없다. Godot 에디터에서 씬을 실행해 확인한다:

- 메인 씬(F5): `Scenes/start.tscn` — 어둠에서 시작하는 실제 게임 도입부
- 맵 에디터: `Scenes/editor.tscn` — 레벨 제작 + TAB으로 즉시 플레이 테스트
- CLI 실행: `godot --path . [res://Scenes/editor.tscn]` (godot이 PATH에 있을 때)

## 코드 규칙

- **camelCase를 쓴다** (GDScript 표준 snake_case가 아님). 기존 스타일을 따를 것
- 주석은 한국어. 수치 튜닝에는 이유를 남긴다 (예: "3블럭(48px) 점프 — 4블럭은 못 넘는다")
- 스크립트 구획은 `# Public` / `# Private` / `# Methods` 주석으로 나눈다
- 물리 보간이 프로젝트 전역에서 켜져 있다 — **위치를 순간이동시키면 반드시 `reset_physics_interpolation()`을 호출**할 것 (잔상 방지). `player_color.gd`의 부활/리셋 처리 참고
- 물리 콜백(`body_entered` 등) 안에서 충돌 형태나 monitoring을 바꿀 때는 `set_deferred`를 쓴다 — `water.gd`의 freeze/unfreeze, `fruit.gd` 참고

## 아키텍처

### 두 세대의 코드가 공존한다

- **현재 게임**: `ColorPlayer`(`Scripts/player_color.gd`) 중심의 색 상태 시스템. 아래 설명 전부 이쪽
- **원본 템플릿**: `Godot platformer source/` 폴더(참고용 사본)와 루트에 남은 `Scripts/player.gd`, `bee.gd`, `projectile.gd`, `gem.gd`, `ui.gd`, `Scenes/game.tscn` — 더블 점프/발사체/벌 적/보석 카운터가 있는 초기 버전. 새 기능은 여기 넣지 말 것

### 색 상태 시스템 (player_color.gd)

핵심 패턴: `ColorState` enum + `STATS` 상수 테이블. **새 상태를 추가하려면 enum 항목과 STATS 수치만 넣으면 된다** — 색은 `Shaders/silhouette.gdshader`의 `tint` 유니폼으로, 눈은 별도 `Eyes` 노드(`eyes.gd`)가 그리므로 스프라이트 교체가 필요 없다.

| 상태 | 능력 | 구현 상태 |
|---|---|---|
| DARK | 점프 불가, 배경색 실루엣 + 빛나는 눈 | 완료 |
| RED | 3블럭 점프 + `"lavaWalk"` 용암 밟기 | 완료 — 용암(`lava.gd`)이 매 프레임 플레이어 상태를 보고 바닥/사망 판정을 전환 |
| BLUE | 1블럭 점프 + `"freeze"` 물 얼리기 | 완료 — 접촉 기반. 물이 `hasAbility("freeze")`를 확인해 연결된 물 전체를 BFS로 얼린다(`water.gd`), 사망 시 `call_group("water", "unfreeze")` |
| GREEN | 2블럭 점프 + `"cling"` 천장 매달리기 | 완료 (`applyGravity`에서 시작, `applyCling`에서 유지) |

점프는 `gravity = -jumpPower * 8` 방식이고 중력 가속은 `gravityPower`(6.4) — 이 두 수는 짝으로 튜닝돼 있어(최대 높이 유지 + 체공 시간, `gravityPower` 주석 참고) 한쪽만 바꾸면 안 된다. 코요테 타임(0.1s)과 점프 버퍼(0.1s)가 있고, 수평 이동은 lerp가 아닌 `move_toward` 가감속이다 — 이 조작감 코드는 주석에 적힌 이유 없이 단순화하지 말 것.

상태 변화는 `stateChanged` 시그널로 발신되며 `start.tscn`에서 맵 밝히기(`start.gd`)와 안내 문구(`start_ui.gd`)가 이를 구독한다.

### 오브젝트 간 결합 방식

노드 참조 대신 덕 타이핑과 그룹을 쓴다:

- 충돌체가 `has_method("die")` / `has_method("eatFruit")` / `has_method("hasAbility")`를 확인해 호출 (water → player, fruit → player)
- 그룹은 `"player"` / `"fruits"` / `"water"` 세 개. `"player"`는 `ColorPlayer.tscn` 루트 노드에 설정돼 있어 어느 씬에 인스턴스화해도 따로 등록할 필요 없다 — `lava.gd`가 `get_first_node_in_group("player")`로 매 프레임 조회한다
- 플레이어 사망 시 `call_group("fruits", "respawn")` — 과일은 먹혀도 `queue_free()` 하지 않고 숨겼다가 되살린다. 같은 방식으로 `call_group("water", "unfreeze")`가 얼음을 물로 되돌린다
- 부활 지점 = 마지막으로 먹은 과일 위치 (`respawnPosition`)

과일(`fruit.gd`)·물(`water.gd`)·용암(`lava.gd`) 모두 "종류 enum + 상수 테이블(텍스처/판정)" 패턴으로, `@export` 변수 하나만 지정해 배치한다. 용암 텍스처(`lava/`)는 물 텍스처의 색상만 빨간색으로 돌린 것이라 판정 수치가 물과 동일하다.

매달림 원웨이 플랫폼(`cling_platform.gd`, `platform/ClingPlatform.tscn`)은 칸 아래쪽 4px에 붙는 원웨이 발판 — 아래에서 점프하면 통과하지만, 플레이어가 천장에 매달린(`clinging`) 동안만 양방향 충돌로 바뀌어 매달린 채 좌우로 지나갈 수 있다. 용암처럼 매 프레임 플레이어 상태를 확인하며, 원웨이 특성상 이 발판에서 매달리기를 새로 시작할 수는 없다.

초록 인간(`green_human.gd`, `npc/GreenHuman.tscn`)은 충돌체 없는 Area2D NPC — 플레이어 스프라이트에 실루엣 셰이더를 어두운 초록으로 입히고 표정(`green_human_face.gd`)만 따로 그린다. 초록 플레이어가 닿으면 잠깐 껴안았다가 3블럭 높이(LAUNCH_POWER 26 = RED 점프)로 띄워 주고, 다른 색 플레이어가 밟으면 화난 표정으로 1블럭(BOUNCE_POWER 17 = BLUE 점프) 튕겨 낸다. 플레이어 쪽 훅은 `hold(duration)`(조작·물리 정지)과 `launch(power)`(jumpPower 단위로 발사) — 둘 다 덕 타이핑으로 부른다.

### 맵 에디터 (Scripts/map_editor.gd)

UI 전부를 코드로 생성하는 단일 스크립트. 알아야 할 것:

- 맵은 `maps/<이름>.json`에 저장 (version 1 포맷: tiles + objects + playerStart) — 에디터 실행 시 `res://maps`(프로젝트 폴더, git으로 공유), export 빌드에서는 `user://maps`. 실행 시 최근 맵 자동 로드, TAB 플레이 전환 시 자동 저장
- `objects` 딕셔너리(셀 → type/variant/node)가 원본 데이터이고 노드는 `rebuildObjects()`로 언제든 재생성된다 — 플레이 중 먹힌 과일 복원도 이 방식
- 플레이 모드는 `ColorPlayer.tscn`을 인스턴스화하고 `resetY`를 맵 높이에 맞춰 넘긴다
- 에디터는 `EDITOR_RESOLUTION`(1920x1080)으로 동작하고(`content_scale_size`를 런타임에 변경), 플레이 모드에서는 project.godot의 게임 해상도로 복원해 실제 게임과 같은 시야로 테스트한다
- 셀 크기 16px. 타일셋(`Sprites/tilemap.tres`)의 모든 타일은 `buildTileTools()`가 `tile_x_y` 이름으로 자동 등록해 팔레트(5x3 격자, ◀ ▶ 페이지 넘김)에 나온다 — 지형(충돌)→장식(통과)→오브젝트 묶음 순 정렬이고 묶음마다 새 줄에서 시작. 이름·단축키가 필요한 타일만 `TILE_TYPES`와 `TOOL_INFO`에 항목 추가 (저장 포맷의 type 문자열이 이 이름이므로 기존 이름 변경 금지)
- 조작법 전체(도구 단축키 1~0·Q/W/E, 방향키 맵 이동, F11 등)는 `map_editor.gd` 상단 주석에 있다 — 도구를 추가하면 그 주석과 `buildUI()`의 도움말 텍스트도 함께 갱신할 것

### 입력 액션 (project.godot)

`left`/`right`(A/D/방향키), `jump`(W/↑/Space), `reset`(R), `shoot`(Space — 템플릿용, ColorPlayer는 사용 안 함). 현재 능력은 전부 자동 발동(접촉/충돌)이라 별도 능력 키가 없다.

## 다음 작업 (인수인계)

1. 맵 에디터로 실제 레벨 제작 (`maps/map1.json` 진행 중, 게임 씬은 시작 씬 하나만 존재)
