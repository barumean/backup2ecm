# backup2ecm

원본폴더(로컬 작업 폴더)와 ECM 백업폴더(네트워크 드라이브) 사이를 자동으로 동기화하는 도구입니다.

- **백업(backup)** : 원본폴더 → ECM폴더. 퇴근 시(또는 지정 시각)에 새로 만들거나 수정한 파일만 ECM으로 복사
- **받아오기(restore)** : ECM폴더 → 원본폴더. ECM에 있는 더 최신 파일을 로컬로 가져오기

robocopy(Windows 기본 내장)를 사용하므로 **별도 프로그램 설치가 필요 없습니다.**
기본 동작은 새/변경 파일만 복사하며 **어떤 파일도 삭제하지 않습니다.**

## 구성 파일

| 파일 | 역할 |
|---|---|
| `config.json` | 원본폴더/ECM폴더 경로, 제외 파일 등 설정 |
| `backup2ecm.ps1` | 실제 동기화 실행 스크립트 |
| `register-schedule.ps1` | 매일 지정 시각 자동 실행 등록/해제 |

## 1. 설정 (`config.json`)

```json
{
  "pairs": [
    {
      "name": "송교항_성과품",
      "enabled": true,
      "source": "D:\\작업\\(C515250)송교항\\성과품",
      "ecm": "Y:\\전사 폴더\\Y. 수행 프로젝트\\12. 항만\\2025년\\(C515250)송교항 어촌신활력증진사업 기본계획 및 실시설계용역\\I. 성과품 관리\\01. 성과품 작업"
    }
  ]
}
```

- `source` : 원본폴더(내 PC의 작업 폴더). **실제 작업 폴더 경로로 수정하세요.**
- `ecm` : ECM 백업폴더(Y: 드라이브 경로)
- JSON 문법상 경로의 `\` 는 반드시 `\\` 로 두 번 써야 합니다.
- 프로젝트가 여러 개면 `pairs` 배열에 항목을 추가하면 됩니다.
- `enabled: false` 로 두면 해당 쌍은 건너뜁니다.
- `excludeFiles` / `excludeDirs` : 복사에서 제외할 파일/폴더 패턴 (임시파일 `~$*`, `*.tmp` 등 기본 포함)

## 2. 수동 실행

PowerShell 을 열고(시작 → "PowerShell" 검색) 이 폴더에서:

```powershell
# 백업: 원본 -> ECM (기본)
.\backup2ecm.ps1

# 받아오기: ECM -> 원본
.\backup2ecm.ps1 -Mode restore

# 실제 복사 없이 무엇이 복사될지 미리 보기
.\backup2ecm.ps1 -DryRun

# 특정 프로젝트만 실행
.\backup2ecm.ps1 -PairName 송교항_성과품
```

> 처음 실행 시 "스크립트 실행이 비활성화" 오류가 나면 아래를 한 번 실행하세요:
> ```powershell
> Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
> ```

## 3. 자동 실행 등록 (퇴근 시 백업)

```powershell
# 매일 18:00 에 자동 백업 (기본)
.\register-schedule.ps1

# 시각 변경 (예: 17:30)
.\register-schedule.ps1 -Time 17:30

# 출근 시 ECM에서 받아오기도 등록하고 싶다면 (예: 08:30)
.\register-schedule.ps1 -Time 08:30 -Mode restore

# 등록 해제
.\register-schedule.ps1 -Remove
```

등록된 작업은 Windows **작업 스케줄러**(`taskschd.msc`)에서 `Backup2ECM_backup` /
`Backup2ECM_restore` 이름으로 확인할 수 있습니다.

- 지정 시각에 PC가 꺼져 있었다면, 다음에 켜졌을 때 밀린 작업이 자동 실행됩니다(`StartWhenAvailable`).
- 네트워크 드라이브(Y:)는 로그인 세션에서만 연결되므로 작업은 "사용자 로그온 시에만 실행"으로 등록됩니다.
  PC를 로그오프/종료한 상태에서는 실행되지 않으니, 퇴근 시 **화면 잠금(Win+L)** 상태로 두면 됩니다.

## 4. 동작 방식

- `robocopy /E /XO` : 하위 폴더 포함, **원본이 더 최신인 파일만** 복사 (대상의 최신 파일은 덮어쓰지 않음)
- 삭제 없음이 기본. 대상 폴더를 원본과 완전히 동일하게(원본에 없는 파일 삭제) 만들려면 `-Mirror` 옵션을 명시적으로 사용:
  ```powershell
  .\backup2ecm.ps1 -Mirror   # 주의: ECM에만 있는 파일이 삭제됩니다
  ```
- 실행 결과는 `logs\` 폴더에 날짜별 로그 파일로 저장되며 30일(설정 가능) 지난 로그는 자동 삭제됩니다.
- Y: 드라이브가 연결되어 있지 않으면 오류를 로그에 남기고 해당 쌍은 건너뜁니다.

## 주의 사항

- 같은 파일을 로컬과 ECM 양쪽에서 **동시에 수정**하면, backup/restore 시 더 최신인 쪽이 남습니다.
  받아오기(restore)를 쓰는 경우 출근 시 restore → 작업 → 퇴근 시 backup 순서를 지키는 것을 권장합니다.
- 한글 경로/파일명은 정상 지원됩니다 (robocopy 유니코드 지원).
