# Pocket SSH 📱

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Android](https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)

**Pocket SSH**는 개발자와 시스템 관리자를 위한 직관적이고 안전한 모바일 SSH 클라이언트입니다.
Android 15 (API 35) 환경에 최적화되어 있으며, Flutter로 개발되었습니다.

## ✨ 주요 기능 (Features)

- **간편한 접속:** Host, Port, User, Password 입력만으로 즉시 연결
- **강력한 인증:** Password 및 Private Key (PEM/PPK) 파일 인증 지원
- **보안 최우선:** 모든 민감 정보는 기기 내부 저장소에만 암호화되어 저장 (서버 전송 X)
- **스니펫(Snippet):** 자주 사용하는 명령어를 저장하여 원터치 실행
- **최신 OS 대응:** Android 15 (API 35) 타겟팅 및 네이티브 빌드 최적화 (R8/ProGuard 적용)

## 📸 스크린샷 (Screenshots)

| 메인 화면 | 터미널 화면 | 설정 화면 |
|:---:|:---:|:---:|
| <img src="" width="200" /> | <img src="" width="200" /> | <img src="" width="200" /> |
## 🛠 빌드 및 실행 방법 (Getting Started)

이 프로젝트는 보안을 위해 **서명 키(Keystore)**와 **설정 파일(key.properties)**이 제외되어 있습니다.
소스코드를 클론한 후 직접 빌드하려면 아래 설정이 필요합니다.

1. **Flutter SDK 설치** 및 환경 설정
2. 프로젝트 클론:
   ```bash
   git clone [https://github.com/YOUR_USERNAME/pocket-ssh.git](https://github.com/YOUR_USERNAME/pocket-ssh.git)
