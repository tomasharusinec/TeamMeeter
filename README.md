# TeamMeeter

Prototyp našej aplikácie možno nájsť na odkaze nižšie:
https://www.figma.com/proto/BCvoS3jhIpU7cmf4nBh6Bq/ZMABT_prototyp?node-id=8-4&p=f&t=i2pHDLNGUbBvG5qk-1&scaling=scale-down&content-scaling=fixed&page-id=0%3A1&starting-point-node-id=8%3A4

Wireframy obrazoviek sa nachádzajú tu:
https://www.figma.com/design/gJSHyvsw6bXx5Kr5vEmICx/ZMABT_wireframes?m=auto&t=boozvboGXBxOCi3n-1

## Inštalácia a spustenie (Backend)

Tento návod slúži na sprevádzkovanie backendovej časti aplikácie.

### 1. Príprava PostgreSQL
Uistite sa, že máte nainštalovaný a spustený PostgreSQL server (predvolene na porte 5432).

### 2. Inštalácia závislostí
Nainštalujte potrebné Python knižnice pomocou príkazu:
```bash
pip install -r requirements.txt
```

### 3. Konfigurácia prostredia (.env)
1. V koreňovom adresári vytvorte súbor `.env` (môžete skopírovať `.env.example`).
2. Vyplňte potrebné údaje:
   - `DB_USER`: Vaše meno používateľa v PostgreSQL (predvolene `postgres`).
   - `MY_PASS`: Vaše heslo k PostgreSQL.
   - `DB_HOST` a `DB_PORT`: Ak bežíte na neštandardných nastaveniach.
   - `JWT_SECRET_KEY`: Náhodný reťazec pre zabezpečenie tokenov (možno použiť predvolený z `.env.example`).
   - `MESSAGE_ENCRYPTION_KEY`: Fernet kľúč pre šifrovanie správ (možno použiť predvolený z `.env.example`).

### 4. Automatická inicializácia databázy
Aplikácia obsahuje skript, ktorý pri prvom spustení automaticky vytvorí databázu a tabuľky podľa schémy. Nemusíte teda nič manuálne vytvárať v pgAdminovi.

### 5. Spustenie servera
Aplikáciu spustíte z koreňového adresára príkazom:
```bash
python backend/main.py
```

### 6. API Dokumentácia
Po úspešnom spustení nájdete interaktívnu dokumentáciu (Swagger) na adrese:
`http://localhost:5000/documentation/`

---

## Inštalácia a spustenie (Frontend – Flutter)

Aplikácia sa nachádza v `frontend/flutter_application_1`. Pred spustením musí byť spustený backend (pozri vyššie).

**Nástroje:** Flutter (Dart aspoň v rozsahu z `pubspec.yaml`), Android Studio (telefón cez USB alebo ladenie cez WiFi), pre **Windows** build ešte Visual Studio. Overenie prostredia: `flutter doctor`.

**Závislosti a beh:**
```bash
cd frontend/flutter_application_1
flutter pub get
flutter run
```

**IP backendu:** v súbore `lib/services/api_service.dart` upravte konštantu **`baseUrl`** v triede `ApiService` podľa toho, kde beží Flask:
- **Fyzický mobil v rovnakej sieti ako PC s backendom** → `http://<PC_IP>:5000` (na PC povoľte port **5000** vo firewalle)

**Firebase súbory:** pre Android patrí do projektu `android/app/google-services.json` (z Firebase konzoly, v repozitári sa nachádza vzorová verzia). Push zo servera používa backend súbor `backend/firebase_service.json` (cesta v `FIREBASE_SERVICE_ACCOUNT_PATH` v `.env`) — bez neho FCM zo servera nepôjde.

Pre správne fungovanie aplikácie pri prvom spustení na telefóne potvrďte požadované oprávnenia.