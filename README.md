# CostWarden — Prototyp click-through

Statyczny prototyp całej ścieżki użytkownika. Bez backendu — dane w dashboardzie są przykładowe, upload/mapping/walidacja działają naprawdę w przeglądarce (parsowanie CSV/XLSX), ale nic się nigdzie nie zapisuje i analiza jest symulowana.

## Strony (w kolejności ścieżki użytkownika)

| Plik | Co to jest |
|---|---|
| `index.html` | Landing page — punkt wejścia |
| `signup.html` | Rejestracja (mock — nie tworzy prawdziwego konta) |
| `create-org.html` | Utworzenie organizacji (mock) |
| `upload.html` | Upload → Mapowanie kolumn → Walidacja → Analiza → Gotowe (parsowanie CSV/XLSX działa naprawdę, reszta mockowana) |
| `dashboard.html` | Główny dashboard: Overview, Findings, Suppliers, Contracts, Reports (dane na sztywno w kodzie) |

## Jak to uruchomić lokalnie

Wystarczy otworzyć `index.html` w przeglądarce — to zwykłe pliki statyczne, nie wymagają serwera ani instalacji.

## Jak to opublikować (GitHub Pages)

1. Wrzuć zawartość tego folderu do repozytorium na GitHubie.
2. W ustawieniach repo: **Settings → Pages → Deploy from branch**, wybierz branch `main` i folder `/ (root)`.
3. Po chwili strona będzie dostępna pod `https://<twoj-user>.github.io/<nazwa-repo>/`.

## Co dalej — podłączenie backendu

Ten prototyp pokazuje wygląd i przepływ. Żeby stał się prawdziwą aplikacją:

1. Załóż projekt w [Supabase](https://supabase.com) i wgraj `costwarden_schema.sql` (Postgres + Auth + Storage + RLS).
2. W `signup.html` i `create-org.html` podłącz formularze pod `supabase.auth.signUp()` i insert do tabeli `organizations` / `org_members`.
3. W `upload.html` podłącz upload pliku pod Supabase Storage i zapis sparsowanych wierszy do tabeli `raw_rows`.
4. Napisz silnik reguł jako Supabase Edge Function — bierze `raw_rows`, liczy `price variance` / `duplicate charge` / `contract drift` / `rate mismatch`, zapisuje wynik do `findings`. Do pola `description` i `recommended_action` wywołuje AI; kwoty i `confidence` liczy wyłącznie kod reguł.
5. W `dashboard.html` podmień tablice `FINDINGS` / `SUPPLIERS` / `CONTRACTS` na zapytania do Supabase (`supabase.from('findings').select()` itd.).
6. Wystaw frontend na Vercel/Netlify, połączony z tym samym repo — każdy push będzie automatycznie publikował zmiany.

Pełny schemat bazy: patrz `costwarden_schema.sql` w tym samym wydaniu.
