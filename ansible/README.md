# WeeWX ja nginx Ansiblella

`site.yml` asentaa Alpine Linuxiin (3.22 tai uudempi) WeeWX:n tämän repon
apk-reposta sekä nginxin, joka näyttää WeeWX:n raportit. Kohteeksi riittää
Alpinen perusasennus (`setup-alpine`) ja SSH-yhteys. Playbook asentaa myös
Pythonin, jota Ansible tarvitsee.

Playbook tekee seuraavat asiat:

- ottaa käyttöön Alpinen `community`-repon ja weewx-alpine-repon. Repon
  allekirjoitusavain tarkistetaan SHA-256-summalla.
- asentaa paketit `weewx`, `weewx-openrc` ja `tzdata` sekä asettaa
  aikavyöhykkeen (oletus `Europe/Helsinki`)
- kirjoittaa `weewx.conf`-tiedostoon aseman ajurin ja sijainnin, suomen
  kielen, metriset yksiköt (`metricwx`) sekä suomalaiset päivämäärät
  (`31.10.2026 14:30`), myös kuvaajiin
- käynnistää WeeWX:n ja lisää sen käynnistykseen (`rc-update`)
- asentaa nginxin, joka näyttää hakemiston `/var/www/html/weewx` osoitteessa
  `http://ASEMA/`

Ajo on idempotentti: kun mikään ei muutu, toinen ajo ei tee muutoksia.
WeeWX käynnistyy uudelleen vain, jos sen paketti tai asetukset muuttuvat.

## Käyttö

Asenna Ansible koneelle, jolta ajat playbookin, ja hae tarvittava kokoelma:

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
cp inventory.example.yml inventory.yml
```

Kirjoita `inventory.yml`-tiedostoon aseman osoite ja sijainti, ja aja:

```bash
ansible-playbook site.yml
```

`inventory.yml` ei mene gittiin. Ensimmäinen raportti syntyy
arkistovälin (oletus 5 minuuttia) jälkeen. Siihen asti nginx vastaa 403.

## Tärkeimmät muuttujat

Kaikki muuttujat oletusarvoineen löytyvät tiedostoista
`roles/weewx/defaults/main.yml` ja `roles/weewx_nginx/defaults/main.yml`.

| Muuttuja | Oletus | Tarkoitus |
|---|---|---|
| `weewx_location`, `weewx_latitude`, `weewx_longitude` | `WeeWX`, `0.0`, `0.0` | Aseman nimi ja sijainti |
| `weewx_altitude` | `[0, meter]` | Korkeus ja yksikkö |
| `weewx_driver` | `weewx.drivers.simulator` | Aseman ajuri, esim. `weewx.drivers.vantage` |
| `weewx_conf` | `{}` | Omat `weewx.conf`-asetukset (katso alla) |
| `weewx_opts` | tyhjä | weewxd:n optiot tiedostoon `/etc/conf.d/weewx`, esim. `--loop-on-init` |
| `weewx_timezone` | `Europe/Helsinki` | Aikavyöhyke. Tyhjällä arvolla järjestelmän asetus säilyy |
| `weewx_lang`, `weewx_unit_system`, `weewx_time_format` | `fi`, `metricwx`, `%d.%m.%Y %H:%M` | Raporttien kieli, yksiköt ja päivämäärämuoto |
| `weewx_package_state` | `present` | `latest` päivittää weewx:n jokaisella ajolla |
| `weewx_nginx_path` | `/` | Raporttien polku, esim. `/weewx/` |
| `weewx_nginx_port`, `weewx_nginx_server_name` | `80`, `_` | nginxin portti ja palvelimen nimi |
| `weewx_nginx_default_server` | `true` | Vastaa kaikkiin nimiin ja ottaa pois nginx-paketin oman 404-oletuspalvelimen |
| `weewx_diskless` | tunnistetaan | Toimiiko Alpine RAM-levyltä (diskless). Oletuksena tunnistetaan juuritiedostojärjestelmästä, tai aseta `true`/`false` |
| `weewx_check_persistence` | `true` | Diskless-tilassa ajo pysähtyy, jos tietokanta katoaisi uudelleenkäynnistyksessä |

### Omat weewx.conf-asetukset

`weewx_conf` yhdistetään tiedostoon `weewx.conf`. Sisäkkäiset sanakirjat ovat
osioita, ja listoista tulee pilkulla erotettuja arvoja. Playbook muuttaa vain
mainitut avaimet, joten muut käsin tehdyt muutokset ja kommentit säilyvät.
Esimerkiksi:

```yaml
weewx_conf:
  StdReport:
    FTP:
      enable: true
      server: ftp.example.com
```

Ajurin playbook vaihtaa komennolla `weectl station reconfigure`, joka lisää
myös ajurin oman osion (esim. `[Vantage]`). Tästä syystä ajuria ei aseteta
`weewx_conf`-muuttujassa.

Jos et halua suomalaisia päivämäärämuotoja `weewx.conf`-tiedostoon, korvaa
`weewx_conf_defaults` omalla versiollasi, josta `StdReport`-osa puuttuu.

## Davis Vantage ja USB-dataloggeri

```yaml
weewx_driver: weewx.drivers.vantage
weewx_opts: --loop-on-init
weewx_conf:
  Vantage:
    port: /dev/ttyUSB0
```

Muuta ei tarvita, koska `weewx`-käyttäjä on paketissa valmiiksi
`dialout`-ryhmässä. Alpinen mdev antaa `/dev/ttyUSB0`:lle oikeudet
`root:dialout 0660` ja lataa loggerin `cp210x`-ajurin automaattisesti.
udevin kanssa (`setup-devd udev`) laite näkyy lisäksi nimellä
`/dev/vantage`. `--loop-on-init` saa weewxd:n yrittämään uudelleen, jos
konsoli ei vastaa heti käynnistyksessä.

## Raspberry Pi ja diskless-tila

Playbook toimii Pillä samoin kuin muuallakin. Pin erityispiirteet (asennustila,
kello ja muistikortti) on kuvattu pää-README:n
[Raspberry Pi -osiossa](../README.md#raspberry-pi).

Alpine Pi -asennukset ovat usein diskless-tilassa, jolloin järjestelmä on
RAM-levyllä. Playbook tunnistaa tilan, koska juuritiedostojärjestelmä on
silloin `tmpfs`. Diskless-tilassa playbook toimii näin:

- Se pysähtyy, jos myös `/var/lib/weewx` on RAM-levyllä, koska tietokanta
  katoaisi uudelleenkäynnistyksessä. Ratkaisuja on kaksi: sys-tila
  (`setup-disk -m sys`) tai data disk -tila, jossa `/var` on levyllä.
- Se pysähtyy, jos apk-välimuisti puuttuu, koska weewx ja nginx katoaisivat
  uudelleenkäynnistyksessä. Ota välimuisti käyttöön komennolla
  `setup-apkcache`.
- Lopuksi se tallentaa muutokset komennolla `lbu commit`, mutta vain jos
  jokin muuttui. Näin toinen ajo antaa yhä `changed=0`.

## HTTPS

nginx kuuntelee vain HTTP:tä. Jos asema näkyy internetiin, lisää varmenne,
esimerkiksi `certbot`-paketilla, tai julkaise raportit HTTPS-välityspalvelimen
takaa.

## Testaus

Playbook on testattu Docker-konteissa Alpine 3.22:lla, 3.24:llä ja edgellä,
kun OpenRC toimii init-järjestelmänä eikä Pythonia ole valmiiksi asennettuna.
Testeissä tarkistettiin seuraavat asiat:

- Ensimmäinen ajo asentaa kaiken, ja toinen ajo antaa `changed=0`.
- nginx näyttää suomenkielisen raportin päivämäärineen (`02.11.2026 12:28`),
  kuvaajat ja almanakan.
- Kun ajuriksi vaihdetaan Vantage, weewxd lukee simuloitua USB-loggeria
  (`/dev/ttyUSB0`), ja raportissa näkyy `Vantage Pro2`. Tämänkin jälkeen
  toinen ajo antaa `changed=0`.
- Simuloitu diskless-tila: ajo pysähtyy, jos tietokanta on RAM-levyllä tai
  apk-välimuisti puuttuu. Oikein asetetussa järjestelmässä ensimmäinen ajo
  tallentaa muutokset `lbu commit`illa, ja toinen ajo antaa `changed=0`.

Oikealla Davis-laitteella tai Raspberry Pillä playbookia ei ole testattu.
