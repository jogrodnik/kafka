# Confluent Platform 8.3.0 Enterprise — jaka dokładnie wersja Apache Kafka jest używana

## Streszczenie wykonawcze

**Confluent Platform 8.3.0 Enterprise jest oparty na linii Apache Kafka 4.3, a bazową wersją upstream dla wydania 8.3.0 jest Apache Kafka 4.3.0.** Confluent nie dystrybuuje jednak brokerów jako binarnie identycznego `apache-kafka-4.3.0`: własne artefakty Kafka mają wersję **`8.3.0-ce`** — np. `org.apache.kafka:kafka-clients:8.3.0-ce`, `org.apache.kafka:kafka-server:8.3.0-ce` i `org.apache.kafka:kafka_2.13:8.3.0-ce` — i zawierają kod Confluent oraz, w razie potrzeby, dodatkowe poprawki względem odpowiadającego upstreamu. citeturn21view0turn21view2turn16view0turn20view0

Najmocniejszym dowodem na dokładny baseline `4.3.0` jest dokumentacja Confluent, która wprost identyfikuje **CP 8.3.0 jako Kafka Streams 4.3.0** i jednocześnie wskazuje, że poprawka obecna w Apache Kafka 4.3.1 **nie znajduje się w CP 8.3.0**. Dlatego określenie CP 8.3.0 EE jako „Kafka 4.3.1” byłoby błędne; poprawne jest **„Confluent Kafka 8.3.0-ce, upstream baseline Apache Kafka 4.3.0”**. citeturn21view1turn21view3

## Łańcuch dowodowy

### Oficjalne mapowanie Confluent Platform do Apache Kafka

Confluent w oficjalnych release notes dla linii 8.3 pisze:

> `Confluent Platform 8.3 ... provides you with Apache Kafka 4.3`

Oficjalna strona:

`https://docs.confluent.io/platform/current/release-notes/index.html`

Wersja 8.3 została wydana 17 czerwca 2026 r., a macierz kompatybilności jednoznacznie mapuje:

| Confluent Platform | Apache Kafka | data wydania linii |
|---|---:|---:|
| **8.3.x** | **4.3.x** | 17 czerwca 2026 |
| 8.2.x | 4.2.x | 4 marca 2026 |
| 8.1.x | 4.1.x | 15 października 2025 |
| 8.0.x | 4.0.x | 11 czerwca 2025 |

Confluent podkreśla przy tym, że **każde wydanie Confluent Platform dostarczane jest z konkretną wersją Kafka**. citeturn21view2

Oficjalne URL-e:

```text
https://docs.confluent.io/platform/current/release-notes/index.html
https://docs.confluent.io/platform/current/installation/versions-interoperability.html
```

Samo `8.3.x → 4.3.x` nie rozstrzyga jeszcze patcha `.0`, `.1` itd. Do tego potrzebne są kolejne dowody.

### Dokładny patch upstream: Apache Kafka 4.3.0

Confluent podaje bezpośrednio dla CP 8.3.0:

> `Confluent Platform 8.3.0 (Kafka Streams 4.3.0)`

Co ważniejsze, ten sam dokument opisuje problem KAFKA-20616/KAFKA-20688 i stwierdza, że poprawka jest dostępna w **Kafka 4.3.1**, natomiast CP 8.3.0 nadal posiada ten problem. Jest to bardzo mocne rozróżnienie pomiędzy kodem `4.3.0` i `4.3.1`. citeturn21view1

Macierz komponentów Confluent dodatkowo podaje:

| Confluent Platform | ksqlDB | Kafka Streams |
|---|---:|---:|
| **8.3.x** | **8.3.0** | **4.3.0** |
| 8.2.x | 8.2.0 | 4.2.0 |
| 8.1.x | 8.1.0 | 4.1.0 |
| 8.0.x | 8.0.0 | 4.0.0 |

citeturn21view3

Po stronie Apache oficjalny tag **Apache Kafka 4.3.0** istnieje w repozytorium Apache pod commitem skróconym `a9ce322`; GitHub wskazuje oznaczenie tagu z 20 maja 2026 r. citeturn16view3

URL:

```text
https://github.com/apache/kafka/releases/tag/4.3.0
https://github.com/apache/kafka/tree/4.3.0
```

W praktyce więc model wersjonowania wygląda tak:

```text
Apache upstream:
    Apache Kafka 4.3.0
             │
             │ fork / rebuild / Confluent patches
             ▼
Confluent Kafka:
    8.3.0-ce
             │
             ├── kafka-clients-8.3.0-ce.jar
             ├── kafka-server-8.3.0-ce.jar
             ├── kafka_2.13-8.3.0-ce.jar
             └── Enterprise extensions / Confluent Server
                         │
                         ▼
              confluentinc/cp-server:8.3.0
```

Stwierdzenie **„upstream baseline = Apache Kafka 4.3.0”** jest zatem oparte na połączeniu: oficjalnego mapowania `8.3.x → 4.3.x`, dokładnego `Kafka Streams 4.3.0` dla CP 8.3.0, wyraźnego odróżnienia od poprawki dostępnej dopiero w upstream 4.3.1 oraz artefaktów Confluent oznaczonych `8.3.0-ce`. citeturn21view1turn21view2turn16view0turn20view0

### Artefakty Maven rzeczywiście nie mają numeru 4.3.0

To bardzo istotny szczegół. Gdy zainstalujesz CP 8.3.0 Enterprise i sprawdzisz pliki JAR, **nie powinieneś oczekiwać nazw `kafka-clients-4.3.0.jar`**. Confluent przebudowuje Kafka w swoim systemie wersjonowania.

Oficjalne repozytorium Maven Confluent zawiera między innymi:

```text
org.apache.kafka:kafka-clients:8.3.0-ce
org.apache.kafka:kafka-server:8.3.0-ce
org.apache.kafka:kafka_2.13:8.3.0-ce
```

Repozytorium `kafka-clients` udostępnia konkretny `kafka-clients-8.3.0-ce.jar` wraz z plikami kontrolnymi `.md5`, `.sha1`, `.sha256` i `.sha512`. citeturn16view0

```text
https://packages.confluent.io/maven/org/apache/kafka/kafka-clients/8.3.0-ce/
```

Analogicznie oficjalne repozytorium zawiera:

```text
https://packages.confluent.io/maven/org/apache/kafka/kafka-server/8.3.0-ce/
```

z:

```text
kafka-server-8.3.0-ce.jar
kafka-server-8.3.0-ce.jar.sha256
kafka-server-8.3.0-ce.jar.sha512
```

citeturn20view0

oraz brokerowy/agregujący artefakt Scala:

```text
https://packages.confluent.io/maven/org/apache/kafka/kafka_2.13/8.3.0-ce/
```

z:

```text
kafka_2.13-8.3.0-ce.jar
kafka_2.13-8.3.0-ce.jar.sha256
kafka_2.13-8.3.0-ce.jar.sha512
```

citeturn19view1

Co ciekawe, indeks Confluent pokazuje dla tej samej wersji zarówno warianty `8.3.0-ce`, jak i `8.3.0-ccs`. W kontekście Confluent **CE oznacza dystrybucję Enterprise**, natomiast CCS jest dystrybucją Community; dokumentacja Confluent używa dokładnie tego rozróżnienia np. dla Kafka Connect. citeturn17view0turn19view0turn21view3

## Mapowanie wersji i artefaktów

Najbardziej użyteczne mapowanie dla **Confluent Platform 8.3.0 Enterprise** wygląda następująco:

| Warstwa / komponent | Wersja dostarczana przez Confluent | Koordynaty / identyfikator | Odpowiednik upstream | Integralność |
|---|---|---|---|---|
| Confluent Platform EE | **8.3.0** | CP release | **Apache Kafka 4.3.0 baseline** | zależnie od RPM/DEB/TAR |
| Confluent Server | **8.3.0** | RPM/DEB `confluent-server` | Kafka 4.3.0 + Confluent | package checksum/signature |
| Docker Enterprise broker | **8.3.0** | `confluentinc/cp-server:8.3.0` | Kafka 4.3.0 + Confluent | OCI `sha256` digest |
| Kafka server module | **8.3.0-ce** | `org.apache.kafka:kafka-server:8.3.0-ce` | Kafka server 4.3.0 baseline | `.sha256`, `.sha512` opublikowane |
| Broker aggregate | **8.3.0-ce** | `org.apache.kafka:kafka_2.13:8.3.0-ce` | Kafka 4.3.0 / Scala 2.13 | `.sha256`, `.sha512` opublikowane |
| Java Kafka client | **8.3.0-ce** | `org.apache.kafka:kafka-clients:8.3.0-ce` | Kafka client 4.3.0 baseline | `.sha256`, `.sha512` opublikowane |
| Kafka Streams | Confluent build / API **4.3.0** | `org.apache.kafka:kafka-streams` | **Apache Kafka Streams 4.3.0** | repo Maven |
| ksqlDB | **8.3.0** | Confluent ksqlDB | Kafka Streams **4.3.0** | repo Confluent |

Źródła dla artefaktów `kafka-clients`, `kafka-server` i `kafka_2.13` są bezpośrednimi indeksami oficjalnego Maven repository Confluent. citeturn16view0turn20view0turn19view1

Enterprise broker jest dystrybuowany jako **Confluent Server**, który według Confluent zawiera Kafka oraz komercyjne możliwości, m.in. RBAC, Tiered Storage i Self-Balancing Clusters. Confluent deklaruje zgodność Confluent Server z Kafka. citeturn21view5

Oficjalny obraz Docker dla tej wersji to:

```text
confluentinc/cp-server:8.3.0
```

Dokumentacja Confluent for Kubernetes używa dokładnie tego tagu jako przykładu aktualizacji Kafka do CP 8.3.0. citeturn26view2

### Checksums

Confluent publikuje sidecary sum kontrolnych. Na przykład dla klienta istnieją:

```text
https://packages.confluent.io/maven/org/apache/kafka/kafka-clients/8.3.0-ce/kafka-clients-8.3.0-ce.jar.sha256

https://packages.confluent.io/maven/org/apache/kafka/kafka-clients/8.3.0-ce/kafka-clients-8.3.0-ce.jar.sha512
```

a dla serwera:

```text
https://packages.confluent.io/maven/org/apache/kafka/kafka-server/8.3.0-ce/kafka-server-8.3.0-ce.jar.sha256

https://packages.confluent.io/maven/org/apache/kafka/kafka-server/8.3.0-ce/kafka-server-8.3.0-ce.jar.sha512
```

oraz:

```text
https://packages.confluent.io/maven/org/apache/kafka/kafka_2.13/8.3.0-ce/kafka_2.13-8.3.0-ce.jar.sha256
```

Ich obecność jest widoczna bezpośrednio w oficjalnych indeksach Confluent. citeturn16view0turn20view0turn19view1

Nie wpisuję tutaj „z pamięci” wartości hash: właściwą wartość należy pobrać z repozytorium dla dokładnie tego artefaktu i porównać z lokalnym JAR-em. To eliminuje również ryzyko pomylenia JAR-u `ce`, `ccs`, sources, javadoc albo test JAR.

## Weryfikacja techniczna na własnej instalacji

### Najszybsza weryfikacja JAR

Na typowej instalacji pakietowej Kafka JAR-y znajdują się pod `/usr/share/java/kafka/`; w archiwum Confluent analogiczna ścieżka jest pod katalogiem `share/java/kafka`. Najbezpieczniej najpierw znaleźć konkretny plik przez manager pakietów.

RPM:

```bash
rpm -q confluent-server

rpm -ql confluent-server \
  | grep -E '/kafka-(clients|server)(-[^/]*)?\.jar$|/kafka_2\.13-.*\.jar$'
```

Dla CP 8.3.0 EE oczekuj artefaktów z rodziną wersji:

```text
8.3.0-ce
```

zamiast:

```text
4.3.0
```

co jest konsekwencją wersjonowania własnych buildów Confluent. Oficjalne repo Maven potwierdza istnienie dokładnie takich artefaktów. citeturn16view0turn20view0turn19view1

Dla DEB:

```bash
dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' \
  confluent-server

dpkg -L confluent-server \
  | grep -E 'kafka-(clients|server).*\.jar|kafka_2\.13-.*\.jar'
```

### Odczyt wersji zapisanej wewnątrz Kafka JAR

Najlepszym miejscem nie zawsze jest `MANIFEST.MF`. Kafka posiada własny plik:

```text
kafka/kafka-version.properties
```

Najpierw znajdź klienta:

```bash
JAR=$(
  find /usr/share/java /opt /usr/lib \
    -type f -name 'kafka-clients-8.3.0-ce.jar' \
    2>/dev/null | head -1
)

printf 'JAR=%s\n' "$JAR"
```

Następnie:

```bash
unzip -p "$JAR" kafka/kafka-version.properties
```

Oczekiwany klucz wersji powinien identyfikować build Confluent w rodzaju:

```text
version=8.3.0-ce
commitId=<commit-builda-Confluent>
```

Dokładny `commitId` jest szczególnie wartościowy: pozwala przejść od zainstalowanego binarium do dokładnego commita źródeł, zamiast opierać się tylko na numerze marketingowym.

Dodatkowo sprawdź manifest:

```bash
unzip -p "$JAR" META-INF/MANIFEST.MF \
  | grep -Ei \
    'Implementation-(Title|Version)|Specification-(Title|Version)|Build|Commit'
```

`MANIFEST.MF` może mieć mniej informacji niż `kafka-version.properties`, dlatego brak `4.3.0` w manifeście **nie oznacza**, że CP nie bazuje na 4.3.0.

### Porównanie sumy SHA-256

Dla `kafka-clients`:

```bash
sha256sum "$JAR"

curl -fsSL \
  'https://packages.confluent.io/maven/org/apache/kafka/kafka-clients/8.3.0-ce/kafka-clients-8.3.0-ce.jar.sha256'
```

Dla `kafka-server`:

```bash
SERVER_JAR=$(
  find /usr/share/java /opt /usr/lib \
    -type f -name 'kafka-server-8.3.0-ce.jar' \
    2>/dev/null | head -1
)

sha256sum "$SERVER_JAR"

curl -fsSL \
  'https://packages.confluent.io/maven/org/apache/kafka/kafka-server/8.3.0-ce/kafka-server-8.3.0-ce.jar.sha256'
```

Obie wartości powinny być identyczne, o ile lokalny JAR pochodzi z dokładnie tego samego opublikowanego artefaktu Maven. Oficjalne indeksy potwierdzają publikowanie plików SHA-256 dla tych JAR-ów. citeturn16view0turn20view0

### RPM i DEB — sprawdzenie wersji pakietu

RPM:

```bash
rpm -q --qf \
  '%{NAME} %{EPOCHNUM}:%{VERSION}-%{RELEASE} %{ARCH}\n' \
  confluent-server
```

oraz:

```bash
rpm -qi confluent-server
```

Jeżeli chcesz zobaczyć wszystkie zależności Kafka w pakiecie:

```bash
rpm -ql confluent-server \
  | grep -i kafka \
  | sort
```

Dla DEB:

```bash
dpkg-query -W \
  -f='Package: ${Package}\nVersion: ${Version}\nArchitecture: ${Architecture}\n' \
  confluent-server
```

oraz:

```bash
dpkg -L confluent-server | grep -i kafka | sort
```

Wynik pakietu mówi o **wersji produktu Confluent 8.3.0**, nie o numerze upstream `4.3.0`. To rozróżnienie jest zamierzone, ponieważ Confluent Server jest osobnym, komercyjnym komponentem zawierającym Kafka i rozszerzenia Confluent. citeturn21view5

### Maven — niezależne potwierdzenie współrzędnych

Możesz pobrać dokładnie ten klient:

```bash
mvn dependency:get \
  -Dartifact=org.apache.kafka:kafka-clients:8.3.0-ce \
  -DremoteRepositories=confluent::default::https://packages.confluent.io/maven/
```

Serwer:

```bash
mvn dependency:get \
  -Dartifact=org.apache.kafka:kafka-server:8.3.0-ce \
  -DremoteRepositories=confluent::default::https://packages.confluent.io/maven/
```

oraz brokerowy agregat Scala:

```bash
mvn dependency:get \
  -Dartifact=org.apache.kafka:kafka_2.13:8.3.0-ce \
  -DremoteRepositories=confluent::default::https://packages.confluent.io/maven/
```

Po pobraniu:

```bash
find ~/.m2/repository/org/apache/kafka \
  -path '*8.3.0-ce*' \
  -type f \
  | sort
```

Powinieneś zobaczyć m.in.:

```text
.../kafka-clients/8.3.0-ce/kafka-clients-8.3.0-ce.jar
.../kafka-server/8.3.0-ce/kafka-server-8.3.0-ce.jar
.../kafka_2.13/8.3.0-ce/kafka_2.13-8.3.0-ce.jar
```

To odpowiada dokładnie artefaktom obecnym w oficjalnym repozytorium Confluent. citeturn16view0turn20view0turn19view1

### Docker `cp-server:8.3.0`

Najpierw:

```bash
docker pull confluentinc/cp-server:8.3.0
```

Tag ten jest oficjalnie używany przez Confluent dla CP 8.3.0. citeturn26view2

Zapisz immutable digest:

```bash
docker image inspect \
  confluentinc/cp-server:8.3.0 \
  --format '{{range .RepoDigests}}{{println .}}{{end}}'
```

Otrzymasz wynik w formie:

```text
confluentinc/cp-server@sha256:<digest>
```

Ten digest jest lepszym identyfikatorem audytowym niż sam tag `8.3.0`, ponieważ jednoznacznie identyfikuje pobrany manifest/obraz.

Możesz też zobaczyć OCI labels:

```bash
docker image inspect \
  confluentinc/cp-server:8.3.0 \
  --format '{{json .Config.Labels}}'
```

Nie należy jednak oczekiwać, że label poda literalnie `Apache Kafka 4.3.0`; najbardziej wiarygodną identyfikacją kodu Kafka są JAR-y znajdujące się wewnątrz.

Aby je znaleźć bez zakładania konkretnej ścieżki:

```bash
cid=$(docker create confluentinc/cp-server:8.3.0)

docker export "$cid" \
  | tar -tf - \
  | grep -E 'kafka-(clients|server)-.*\.jar|kafka_2\.13-.*\.jar' \
  | sort -u

docker rm "$cid"
```

Powinieneś znaleźć warianty `8.3.0-ce`.

Jeżeli widzisz ścieżkę przykładowo:

```text
usr/share/java/kafka/kafka-clients-8.3.0-ce.jar
```

możesz wyciągnąć JAR:

```bash
cid=$(docker create confluentinc/cp-server:8.3.0)

docker cp \
  "$cid:/usr/share/java/kafka/kafka-clients-8.3.0-ce.jar" \
  /tmp/kafka-clients-8.3.0-ce.jar

docker rm "$cid"

unzip -p \
  /tmp/kafka-clients-8.3.0-ce.jar \
  kafka/kafka-version.properties

sha256sum /tmp/kafka-clients-8.3.0-ce.jar
```

### Broker startup log

Przy diagnostyce działającego systemu warto również poszukać wpisów Kafka startup:

```bash
journalctl -u confluent-server \
  | grep -E 'Kafka version|Kafka commitId|Kafka startTimeMs'
```

albo dla Kubernetes:

```bash
kubectl logs <kafka-pod> \
  | grep -E 'Kafka version|Kafka commitId|Kafka startTimeMs'
```

Kluczowa interpretacja jest następująca:

```text
Kafka version: 8.3.0-ce
```

oznacza **wersję binarnego builda Confluent**, a nie twierdzenie, że istnieje upstream „Apache Kafka 8.3.0”. Upstream dla tej linii jest Kafka 4.3.x, a dla wydania bazowego CP 8.3.0 — 4.3.0. Oficjalna dokumentacja Confluent oraz Maven artifacts potwierdzają ten dwupoziomowy model wersjonowania. citeturn21view2turn16view0

## Różnice względem czystego Apache Kafka

### Nie jest to byte-for-byte Apache Kafka 4.3.0

To najważniejszy caveat. Nie należy interpretować:

```text
CP 8.3.0 = Apache Kafka 4.3.0
```

jako:

```text
sha256(cp-kafka.jar) == sha256(apache-kafka-4.3.0.jar)
```

Confluent sam stwierdza, że wersja Kafka zawarta w Confluent Platform jest kompatybilna z odpowiadającym wydaniem open-source i może zawierać **dodatkowe poprawki krytycznych błędów**, jeżeli cykle wydawnicze Apache Kafka i Confluent nie są zsynchronizowane. citeturn21view4

Dlatego bardziej precyzyjna nomenklatura architektoniczna to:

> **CP 8.3.0 EE = Confluent Kafka build 8.3.0-ce, zgodny z / bazujący na Apache Kafka 4.3.0, z możliwymi Confluent backportami i dodatkowymi zmianami.**

### Enterprise dodaje kod, którego nie ma w Apache Kafka

`cp-server` nie jest tylko zmianą nazwy Apache Kafka. Confluent Server zawiera Kafka oraz komercyjne funkcje Confluent, w tym między innymi RBAC, Tiered Storage i Self-Balancing Clusters. citeturn21view5

Javadoc Confluent dla `clients 8.3.0-ce` ujawnia również klasy i stałe specyficzne dla Confluent, np. elementy związane z tenantami i autoryzacją, co pokazuje, że artefakty `org.apache.kafka:*:8.3.0-ce` nie są mechanicznym rename'em stockowych JAR-ów Apache. citeturn24search7

### Confluent prowadzi własny fork Kafka

Publiczne repozytorium:

```text
https://github.com/confluentinc/kafka
```

jest forkiem/mirrorem repozytorium Apache Kafka. citeturn26view0

Tagi Confluent są prowadzone we własnym schemacie wersjonowania/buildów:

```text
https://github.com/confluentinc/kafka/tags
```

citeturn26view1

Nie należy więc szukać wyłącznie tagu `4.3.0` w repo Confluent i zakładać, że dokładnie taki commit znajduje się w produkcyjnym `cp-server`. Najlepszy proces audytowy to:

```text
running JAR
   ↓
kafka/kafka-version.properties
   ↓
commitId
   ↓
confluentinc/kafka
   ↓
porównanie z upstream tag apache/kafka:4.3.0
```

Apache upstream `4.3.0` jest oznaczony na oficjalnym repozytorium Apache, m.in. commitem/tagiem widocznym jako `a9ce322`. citeturn16view3

### Możliwe backporty oznaczają „4.3.0 plus”, ale nie „4.3.1”

Istotna subtelność polega na tym, że Confluent może cherry-pickować pojedyncze poprawki z późniejszego rozwoju Kafka bez zmiany całego baseline'u na następną wersję Apache. Confluent oficjalnie mówi o dodatkowych critical bug patches w swojej dystrybucji. citeturn21view4

Nie można zatem wnioskować:

```text
znalazłem commit, który później wystąpił w Apache Kafka 4.3.1
→ zatem CP 8.3.0 to Kafka 4.3.1
```

To byłoby niepoprawne.

W drugą stronę mamy wręcz konkretny kontrprzykład: Confluent informuje, że CP 8.3.0 / Kafka Streams 4.3.0 ma memory leak, którego poprawka jest dostępna w **Apache Kafka 4.3.1**. Oznacza to, że przynajmniej ten fix z 4.3.1 nie trafił do CP 8.3.0 i dokumentacja nadal identyfikuje komponent jako 4.3.0. citeturn21view1

### Version skew pomiędzy numerem CP, API a JAR-em

W jednym środowisku możesz więc legalnie zobaczyć wszystkie poniższe numery:

```text
Confluent Platform       8.3.0
cp-server Docker         8.3.0
confluent-server RPM     8.3.0...
Kafka JAR                8.3.0-ce
Kafka API/upstream line  4.3.x
upstream baseline        4.3.0
Kafka Streams upstream   4.3.0
metadata.version         4.3-...
kraft.version            osobny feature version
```

Te numery opisują **różne warstwy** i nie są ze sobą sprzeczne. Szczególnie `metadata.version` i `kraft.version` nie są numerami wersji binariów Kafka.

Jest to również istotne w kontekście KRaft: Confluent dokumentuje, że linie od CP 7.9/Kafka 3.9 obsługują dynamic controllers według KIP-853, a od CP 8.0 ZooKeeper został usunięty i wymagany jest KRaft. Zatem CP 8.3.0 / Kafka 4.3 jest już jednoznacznie generacją KRaft-only. citeturn21view3

## Wniosek

Dla **Confluent Platform 8.3.0 Enterprise Edition** najbardziej precyzyjna odpowiedź brzmi:

```text
Confluent Platform:      8.3.0 Enterprise
Confluent Kafka build:   8.3.0-ce
Apache Kafka line:       4.3.x
Apache upstream baseline: 4.3.0
Kafka Streams upstream:  4.3.0

Docker:
confluentinc/cp-server:8.3.0

Główne Kafka artifacts:
org.apache.kafka:kafka-clients:8.3.0-ce
org.apache.kafka:kafka-server:8.3.0-ce
org.apache.kafka:kafka_2.13:8.3.0-ce
```

Confluent oficjalnie mapuje CP 8.3.x do Kafka 4.3.x, dla CP 8.3.0 jednoznacznie podaje Kafka Streams 4.3.0, a jego własne repozytorium publikuje Kafka JAR-y pod wersją `8.3.0-ce`; jednocześnie Confluent zastrzega, że ich Kafka może zawierać dodatkowe poprawki krytycznych błędów względem odpowiadającego upstreamu. Z tego względu **„Apache Kafka 4.3.0 baseline + Confluent 8.3.0-ce patches/extensions” jest technicznie dokładniejsze niż samo „Kafka 4.3.0”**. citeturn21view1turn21view2turn21view4turn16view0turn20view0