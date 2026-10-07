/// ISO 639-3 (GlotLID's `deu_Latn`) → ISO 639-1 for the common languages,
/// so text-LID labels compare against the routing table's two-letter codes.
String normaliseLangCode(String raw) {
  var c = raw.trim().toLowerCase();
  if (c.startsWith('__label__')) c = c.substring(9);
  final us = c.indexOf('_');
  if (us > 0) c = c.substring(0, us);
  final dash = c.indexOf('-');
  if (dash > 0) c = c.substring(0, dash);
  const three = {
    'deu': 'de',
    'eng': 'en',
    'fra': 'fr',
    'spa': 'es',
    'ita': 'it',
    'por': 'pt',
    'nld': 'nl',
    'pol': 'pl',
    'rus': 'ru',
    'ukr': 'uk',
    'zho': 'zh',
    'cmn': 'zh',
    'jpn': 'ja',
    'kor': 'ko',
    'ara': 'ar',
    'arb': 'ar',
    'tur': 'tr',
    'ces': 'cs',
    'swe': 'sv',
    'dan': 'da',
    'hin': 'hi',
    'ell': 'el',
    'fin': 'fi',
    'hun': 'hu',
    'ron': 'ro',
    'bul': 'bg',
    'hrv': 'hr',
    'srp': 'sr',
    'slk': 'sk',
    'slv': 'sl',
    'nor': 'no',
    'nob': 'no',
    'cat': 'ca',
    'heb': 'he',
    'vie': 'vi',
    'ind': 'id',
    'tha': 'th',
    'fas': 'fa',
    'pes': 'fa',
    'est': 'et',
    'lit': 'lt',
    'lav': 'lv',
    'ekk': 'et',
    'lvs': 'lv',
  };
  return three[c] ?? c;
}
