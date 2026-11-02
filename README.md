# WeeWX Alpine Linuxille

Alpine-paketti (APKBUILD + OpenRC) [WeeWX](https://weewx.com/)-sääasemaohjelmistolle,
versio 5.5.2. WeeWX:ää ei ole Alpinen aportsissa (ei edes `testing`-repossa),
mutta kaikki sen riippuvuudet löytyvät Alpinen `community`-reposta, joten pip:iä
tai virtualenviä ei tarvita.

Valmiit paketit ovat apk-repossa osoitteessa
<https://iiseppi.github.io/weewx-alpine/> Alpine-versioille 3.22, 3.23, 3.24 ja
edge, kaikille Alpinen arkkitehtuureille (x86_64, aarch64, armv7, armhf…).

Paketti rakentuu, ja 296 upstreamin testiä menee läpi kaikilla neljällä
Alpine-versiolla. Alpine 3.24:llä on lisäksi kokeiltu, että palvelu käynnistyy
OpenRC:llä, simulaattori kirjoittaa tietokantaan ja Seasons-raportti syntyy.
Myös päivitys r0 → r1 on kokeiltu.

## Asennus

Ota `community`-repo käyttöön (`/etc/apk/repositories`) ja aja rootina:

```bash
wget -P /etc/apk/keys https://iiseppi.github.io/weewx-alpine/47714239+iiseppi@users.noreply.github.com-6ae840cb.rsa.pub
```

```bash
echo "https://iiseppi.github.io/weewx-alpine/v$(cut -d. -f1,2 /etc/alpine-release)" >> /etc/apk/repositories
```

```bash
apk add weewx weewx-openrc tzdata
```

Edgellä lisää riviksi `https://iiseppi.github.io/weewx-alpine/edge`. Tämän
jälkeen `apk upgrade` päivittää myös weewx:n.

Määritä asema ja käynnistä se:

```bash
weectl station reconfigure --config=/etc/weewx/weewx.conf
rc-service weewx start
rc-update add weewx
```

Paketti ei käynnistä palvelua itse, kuten Alpinessa on tapana (Debian-paketti
käynnistää).

## Tiedostot

| Tiedosto | Tarkoitus |
|---|---|
| `weewx/APKBUILD` | Paketin resepti |
| `weewx/weewx.initd` | OpenRC-palvelu (`supervise-daemon`), tukee useaa asemaa |
| `weewx/weewx.confd` | Palvelun asetukset (`/etc/conf.d/weewx`) |
| `weewx/weewx.pre-install` | Luo `weewx`-käyttäjän ja lisää sen `dialout`-ryhmään |
| `weewx/weewx.post-install`, `weewx.post-upgrade` | Ohjeet asennuksen ja päivityksen jälkeen |
| `build.sh` | Rakentaa paketit Docker-kontissa |
| `mkrepo.sh` | Kokoaa paketeista apk-repon hakemistoon `site/` |
| `publish.sh` | Julkaisee `site/`-hakemiston gh-pages-haaraan (GitHub Pages) |

## Hakemistorakenne

Sama kuin upstreamin omissa deb/rpm-paketeissa, joten
[WeeWX:n dokumentaatio](https://weewx.com/docs/latest/usersguide/where/) pätee
sellaisenaan (kohta "Debian"):

| Mitä | Missä |
|---|---|
| Ohjelmakoodi (`BIN_ROOT`) | `/usr/share/weewx` |
| `WEEWX_ROOT`: `weewx.conf`, `skins/`, `bin/user/`, `examples/` | `/etc/weewx` |
| SQLite-tietokanta | `/var/lib/weewx` |
| HTML-raportit | `/var/www/html/weewx` |
| Komennot | `/usr/bin/weewxd`, `/usr/bin/weectl` |

Aliopaketit: `weewx-openrc`, `weewx-pyc`, `weewx-doc`, `weewx-bash-completion`
ja `weewx-udev`. Ne asentuvat automaattisesti, kun vastaava järjestelmän osa
(openrc, pyc, bash-completion, udev) on asennettu.

### Asenna myös tzdata

Ilman `tzdata`-pakettia Alpine käyttää UTC-aikaa, jolloin päivän vaihtuminen,
päiväyhteenvedot ja raporttien kellonajat menevät väärin. Aseta aikavyöhyke
komennolla `setup-timezone Europe/Helsinki`.

### Lokit

WeeWX kirjoittaa syslogiin (`/dev/log`). Alpinen oletuksena busyboxin `syslogd`
kirjoittaa tiedostoon `/var/log/messages`. Jos syslog ei ole käynnissä (esim.
kontissa), `weectl` tulostaa pitkiä `Logging error`-virheilmoituksia, mutta
toimii silti. Esimerkkiasetukset rsyslogille ja logrotatelle ovat hakemistossa
`/usr/share/weewx/weewx_data/util/`.

## Sääaseman laitteisto

- **Sarjaportti ja USB-sarjaportti** (Vantage, CC3000, WS23xx, Ultimeter…):
  mdev antaa laitteille `/dev/ttyS*` ja `/dev/ttyUSB*` oikeudet `root:dialout`.
  `weewx`-käyttäjä on `dialout`-ryhmässä, joten muuta ei tarvita.
- **USB HID -asemat** (FineOffsetUSB, AcuRite, WMR100/200/300, TE923, WS28xx):
  mdev luo `/dev/bus/usb`-laitteet `root:root 0660` -oikeuksilla, joten
  `weewx` ei pääse niihin. Helpoin ratkaisu on vaihtaa udeviin komennolla
  `setup-devd udev`. Silloin `weewx-udev` asentuu automaattisesti ja
  upstreamin säännöt antavat laitteet `weewx`-ryhmälle. Tätä ei ole testattu
  oikealla laitteella.
- Jos asema ei vastaa heti käynnistyksessä, lisää `/etc/conf.d/weewx`-tiedostoon
  `weewx_opts="--loop-on-init"`. Muuten supervise-daemon luovuttaa viiden
  epäonnistuneen käynnistysyrityksen jälkeen (`/etc/rc.conf`:n oletus).

## Raporttien julkaisu verkkoon

Raportit ovat staattisia tiedostoja hakemistossa `/var/www/html/weewx`. Esimerkiksi
nginxillä (`apk add nginx`), tiedostossa `/etc/nginx/http.d/weewx.conf`:

```nginx
server {
    listen 80;
    location /weewx/ {
        alias /var/www/html/weewx/;
    }
}
```

Upstreamin esimerkit nginxille ja apachelle löytyvät hakemistosta
`/usr/share/weewx/weewx_data/util/`.

## Useampi asema

```bash
cp /etc/weewx/weewx.conf /etc/weewx/toinen.conf   # vaihda tietokanta ja HTML_ROOT
ln -s weewx /etc/init.d/weewx.toinen
rc-service weewx.toinen start
```

Instanssi lukee ensin tiedoston `/etc/conf.d/weewx` ja sitten tiedoston
`/etc/conf.d/weewx.toinen`. Lokimerkintöjen tunniste on `weewxd-toinen`.

## Päivitys

Kun ajat `apk upgrade`, muokattu `weewx.conf` säilyy ja uusi versio tallentuu
nimellä `weewx.conf.apk-new` (Alpinen normaali käytös). Saat konfiguraation
uuden version mukaiseksi näin:

```bash
weectl station upgrade --config=/etc/weewx/weewx.conf --what config
rm /etc/weewx/weewx.conf.apk-new
rc-service weewx restart
```

Sama pätee skin-tiedostoihin: muuttamattomat päivittyvät, muokatuista tulee
`.apk-new`.

## Erot Debian-pakettiin

- Debconf-kyselyjä ei ole. Paketti asentuu simulaattoriajurilla, ja asema
  määritetään komennolla `weectl station reconfigure`.
- systemd-yksiköiden tilalla on OpenRC-skripti. `weewx@.service`-mallia
  vastaavat `weewx.NIMI`-symlinkit.
- Asentavaa käyttäjää ei lisätä `weewx`-ryhmään automaattisesti. Lisää itsesi
  komennolla `addgroup KÄYTTÄJÄ weewx`, jos haluat muokata asetuksia ja asentaa
  laajennuksia ilman rootia.
- MySQL/MariaDB-tuki ei kuulu riippuvuuksiin. Asenna se tarvittaessa:
  `apk add py3-pymysql`.
- musl-libc ei tue lokaaleja. Jos skin käyttää `%x`-päivämäärämuotoa, vuosi
  näkyy kaksinumeroisena (`09/03/10`, glibc:llä `09/03/2010`). Halutessasi
  aseta muodot itse skin.conf-tiedoston `[Units][[TimeFormats]]`-osiossa.

## Testit

`check()` ajaa upstreamin testit muilta osin, mutta jättää pois seuraavat:

- MySQL-palvelinta vaativat testit
- kaksi testiä, jotka eivät toimi rootina (abuild ajaa testit `-F`-tilassa rootina)
- `test_report_engine`, joka odottaa glibc:n en_US-päivämäärämuotoa

Testit tarvitsevat `tzdata`-paketin, koska ne käyttävät aikavyöhykettä
America/Los_Angeles.

## Rakentaminen ja julkaisu

Tarvitset Dockerin (tai OrbStackin). Paketti on `noarch`, joten Macilla
rakennettu paketti toimii kaikilla arkkitehtuureilla.

```bash
./build.sh 3.22 3.23 3.24 edge
```

Paketit menevät hakemistoon `packages/<versio>/weewx-alpine/<arch>/`.
Ensimmäisellä kerralla skripti luo allekirjoitusavaimen hakemistoon `keys/`.
Yksityinen avain `keys/*.rsa` ei kuulu gitiin (`.gitignore` estää sen).
Ota siitä varmuuskopio: ilman sitä uusia paketteja ei voi allekirjoittaa
samalla avaimella, jolloin käyttäjien pitäisi vaihtaa avain.

Uuden weewx-version julkaisu:

1. Vaihda `weewx/APKBUILD`-tiedostoon uusi `pkgver` ja `pkgrel=0`. Jos
   muutat pelkkää paketointia, kasvata `pkgrel`-arvoa.
2. Rakenna: `./build.sh 3.22 3.23 3.24 edge`
3. Kokoa repo: `./mkrepo.sh`
4. Commitoi ja pushaa lähteet, ja julkaise repo: `./publish.sh`

`publish.sh` korvaa gh-pages-haaran joka kerta, joten vanhat paketit eivät
kerry repon historiaan.

## Aportsiin lähettäminen

APKBUILD noudattaa aportsin käytäntöjä, joten sen voi lähettää
[aportsiin](https://gitlab.alpinelinux.org/alpine/aports) hakemistoon
`testing/weewx`. Ennen sitä:

- tarkista Maintainer-rivi
- aja `apkbuild-lint`
- testaa USB-asema eudevillä
