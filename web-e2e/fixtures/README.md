# Speech fixtures

`jfk.wav` is the existing 11-second Kennedy public-address test fixture.

`fleurs-fr_fr.wav` and `fleurs-de_de.wav` are real recorded speech from Google's
[FLEURS-R dataset](https://huggingface.co/datasets/google/fleurs-r), licensed
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Attribution: Google,
FLEURS dataset authors/contributors. See the
[FLEURS paper](https://arxiv.org/abs/2205.12446).

The original test records, immutable source revision, archive member names,
transcripts and resulting file checksums are recorded in `fleurs.json`.
Changes: converted to mono, 16 kHz PCM16 WAV with FFmpeg. Tests may concatenate
or add deterministic background noise; those transformations are recorded in
their result artifacts. These fixtures are test data and are not app assets.
