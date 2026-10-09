# WirePlumber configuration

`51-imac-audio-names.conf` renames the CS8409 codec's ALSA nodes.

WirePlumber publishes them as "CS8409/CS42L83 Analog" — the codec part number,
which tells a user nothing. The shell prefers a node's nickname over its
description, so overriding the nickname is what actually changes the label in
the volume panel:

```
before:  CS8409/CS42L83 Analog
after:   iMac Audio            (output)
         iMac Microphone       (input)
```

The output is "iMac Audio" rather than "iMac Speakers" because speakers and
headphones are two ports on this one device: it is the same entry whether or not
something is plugged into the jack, so naming it for either port would be wrong
half the time.

Install:

```bash
sudo install -Dm644 51-imac-audio-names.conf \
  /etc/wireplumber/wireplumber.conf.d/51-imac-audio-names.conf
```

`wireplumber.service` has no reload job, so a config change takes effect on the
next login. It is a user-session unit; no restart of PipeWire is required.
