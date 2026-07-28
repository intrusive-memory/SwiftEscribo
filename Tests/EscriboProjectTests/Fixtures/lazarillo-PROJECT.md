---
type: project
title: The Life of Lazarillo de Tormes
author: Anonymous
created: 2025-02-03T00:00:00Z
description: "A modern English translation of \"La Vida de Lazarillo de Tormes,\" the anonymous 16th-century Spanish picaresque novel that follows a young boy's journey through service to various masters in Renaissance Spain."
season: 1
episodes: 8
genre: Literature/Fiction
tags: [picaresque, spanish-literature, renaissance, translation, classic-literature, satire]
episodesDir: episodes
audioDir: audio
filePattern: "*.fountain"
exportFormat: m4a
tts:
  model: "0.6b"
cast:
  # ── PRINCIPAL CAST ──────────────────────────────────────────────
  - character: LAZARO
    aliases: [LAZARO, NARRATOR]
    episodes: [0, 1, 2, 3, 4, 5, 6, 7]
    voiceDescription: "Adult Lazaro — narrator and protagonist across all episodes"
    voicePrompt: "A man in his early 40s, Slight European Spanish accent, with a warm but weathered timbre suggesting a life of hard experience. His tone is measured and sardonic, with dry understated wit and the quiet authority of a survivor who chooses his words carefully. He speaks at a relaxed, deliberate pace with slight gravelly texture — not rough, but seasoned — and wry warmth when reflecting on the absurdities of fate and human vanity."
    voices:
      voxalta: voices/lazaro.vox
  - character: YOUNG LAZARO
    aliases: [LAZARILLO]
    episodes: [1, 2, 3, 5]
    voiceDescription: "Boy Lazaro — the child protagonist, age 10-14"
    voicePrompt: "A male voice in the 10-to-12-year-old range, American English, clear and slightly higher in pitch but not cartoonishly young. Early lines carry genuine openness and curiosity; later lines carry a tightness and flatness — the voice of a child who has decided to stop being one. Capable of delivering sarcasm with eerie calm, with an undercurrent of street-smart cunning hiding beneath vulnerability."
    voices:
      voxalta: voices/young-lazaro.vox
  - character: BLIND MAN
    episodes: [1, 7]
    voiceDescription: "First master — cunning beggar-priest and con man"
    voicePrompt: "A male voice in his 60s, American English with a smooth, oily gravitas — the voice of a man who has talked his way out of every corner life has thrown at him. Capable of warmth that turns cold in an instant. Rich and resonant, with theatrical precision and a performer's control of tempo; the laughter is genuine but never kind. Gravelly and raspy with the cunning energy of a street survivor."
    voices:
      voxalta: voices/blind-man.vox
  - character: ANTONA
    aliases: [MOTHER]
    episodes: [1]
    voiceDescription: "Lazaro's mother — resilient washerwoman"
    voicePrompt: "A female voice in her late 30s to mid-40s, American English, medium-low register with a warm but worn quality. Steady and composed even when emotional — the kind of voice that holds back tears through sheer will. Gentle but never soft; there is iron underneath. Slow, deliberate delivery with quiet dignity; each word chosen carefully because there may not be another chance."
    voices:
      voxalta: voices/antona.vox
  - character: PRIEST
    episodes: [2]
    voiceDescription: "Second master — miserly clergyman of Maqueda"
    voicePrompt: "A man in his mid-50s, American English with a clipped, self-righteous, and slightly nasal quality — the voice of institutional authority weaponized against the powerless. He speaks with an air of false benevolence, smooth and controlled, but with an underlying tightness that reveals paranoia and greed lurking beneath the pious surface."
    voices:
      voxalta: voices/priest.vox
  - character: SQUIRE
    episodes: [3]
    voiceDescription: "Third master — prideful gentleman fallen on hard times"
    voicePrompt: "A male voice in his mid-40s, American English with a formal, measured cadence and exaggerated dignity — as if every word is a pronouncement. Resonant and controlled baritone, with a stiff, performative quality that betrays deep insecurity beneath the pomposity. Occasional warmth breaks through when his guard drops around food."
    voices:
      voxalta: voices/squire.vox
  - character: PARDONER
    episodes: [5]
    voiceDescription: "Fifth master — theatrical indulgence seller and con artist"
    voicePrompt: "A rich, commanding American male voice, mid-40s, with the polished projection of a preacher or carnival barker — honey-smooth when persuading, thunderously righteous when performing piety. Naturally charismatic and slightly larger-than-life, capable of shifting in an instant from intimate warmth to grandiose religious fervor, with an undertone of barely concealed theatrical calculation."
    voices:
      voxalta: voices/pardoner.vox
  - character: CONSTABLE
    episodes: [3, 5]
    voiceDescription: "Law officer — gruff, authoritative, dry humor"
    voicePrompt: "A gruff, authoritative American male voice, late 30s to mid-40s, with the clipped blunt delivery of a man used to giving commands. Pragmatic baritone with a dry sense of humor that surfaces unexpectedly. Capable of shifting from commanding official tone to raw physical energy, and from stern professionalism to conspiratorial laughter."
    voices:
      voxalta: voices/constable.vox
  - character: ARCHPRIEST
    episodes: [7]
    voiceDescription: "Lazaro's patron — smooth, powerful churchman"
    voicePrompt: "A 60s American male voice that is rich, unhurried, and authoritative — the voice of institutional power dressed in warmth. The tone is that of a man who has perfected the art of sounding magnanimous while exercising total control, with a faint unctuousness that never quite crosses into obviousness. Slightly formal diction, confident and expansive, the cadence of someone who expects to be listened to."
    voices:
      voxalta: voices/archpriest.vox
  - character: CHAPLAIN
    episodes: [6]
    voiceDescription: "Sixth master — pragmatic cathedral administrator"
    voicePrompt: "An older American male voice, 60s, with a flat authoritative baritone and the clipped efficiency of someone accustomed to giving instructions rather than having conversations. No warmth, but no malice either — purely pragmatic, with the practiced detachment of an administrator who has managed people for decades."
    voices:
      voxalta: voices/chaplain.vox
  # ── SUPPORTING CAST ─────────────────────────────────────────────
  - character: ZAIDE
    episodes: [1]
    voiceDescription: "Lazaro's stepfather — warm, strong African stable hand"
    voicePrompt: "A male voice in his mid-30s, deep and resonant, American English with a warm, round baritone quality. Full of easy laughter and physical confidence. The delivery is playful and tender even when the words are coarse — the voice of a man who is at ease in his body and genuinely delighted by his child."
    voices:
      voxalta: voices/zaide.vox
  - character: WIFE
    aliases: [WOMAN]
    episodes: [1, 7]
    voiceDescription: "Lazaro's wife — same character as WOMAN in Treatise 1"
    voicePrompt: "A 30s American female voice with a plainspoken, practical quality — no affectation, working-class dignity. In neutral moments she is soft and slightly fretful. When emotional, the voice breaks open with genuine anguish and wounded pride, the sound of someone who has survived by being invisible suddenly forced into full exposure."
    voices:
      voxalta: voices/wife.vox
  - character: NEIGHBOR WOMAN
    episodes: [3, 4]
    voiceDescription: "Kind Toledo neighbor — maternal protector of Young Lázaro"
    voicePrompt: "A female voice in her 40s-50s, American English, warm and earnest with a plain-spoken maternal quality. Gentle but firm when defending the boy — the voice of everyday human decency, unhurried and unpretentious. Practical and no-nonsense, slightly rough around the edges, the kind of voice that has given a lot of well-meaning advice."
    voices:
      voxalta: voices/neighbor-woman.vox
  - character: NOTARY
    episodes: [3]
    voiceDescription: "Legal official — precise, bureaucratic"
    voicePrompt: "A male voice in his 40s-50s, American English, precise and bureaucratic. A slightly nasal, officious quality — he is a man of paperwork and procedure. His laughter when it comes is surprised, breaking through his professional composure."
    voices:
      voxalta: voices/notary.vox
  - character: GOOD MAN
    episodes: [5]
    voiceDescription: "Frightened villager from the Pardoner's congregation"
    voicePrompt: "A middle-aged American male voice, 40s, plainspoken and earnest, with a slightly breathless quality suggesting genuine alarm. The tone is humble and supplicating, the voice of an ordinary man addressing someone he believes holds spiritual power — no artifice, just urgent sincerity."
    voices:
      voxalta: voices/good-man.vox
  - character: TINKER
    episodes: [2]
    voiceDescription: "Traveling repairman — unwitting tool in Lázaro's scheme"
    voicePrompt: "A working-class American male voice, late 40s, with a gruff, no-nonsense quality — the voice of a tradesman who is friendly but not chatty. His tone is casual and direct, slightly rough around the edges, with the easy confidence of someone who does honest work and asks no questions."
    voices:
      voxalta: voices/tinker.vox
  # ── MINOR / ONE-LINE ROLES ─────────────────────────────────────
  - character: LITTLE BROTHER
    episodes: [1]
    voiceDescription: "Lazaro's toddler half-brother — one line"
    voicePrompt: "A very young child's voice, male, 2-3 years old. High-pitched, squeaky, breathless, and guileless. American English, with the halting cadence of a toddler who has just learned a word and delivers it with full earnestness and no irony whatsoever."
    voices:
      voxalta: voices/little-brother.vox
  - character: NEIGHBOR
    episodes: [2, 7]
    voiceDescription: "Neighborhood gossip — conspiratorial, well-meaning"
    voicePrompt: "A middle-aged American male voice, conspiratorial and slightly hushed, with the warm tone of a neighborhood gossip who enjoys having a theory. Eager and a touch fussy, the voice of a man who enjoys knowing things and sharing them, casual and unhurried."
    voices:
      voxalta: voices/neighbor.vox
  - character: WIDOW
    episodes: [3]
    voiceDescription: "Mourning woman at funeral procession"
    voicePrompt: "A middle-aged American female voice, raw and loud with theatrical grief — rising and falling in a keening wail. The voice cracks with genuine-sounding anguish but carries an almost operatic quality of public mourning. High emotional register, slightly overwrought."
    voices:
      voxalta: voices/widow.vox
  - character: OLD WOMAN
    episodes: [3]
    voiceDescription: "Elderly bed-rental creditor"
    voicePrompt: "A female voice in her 60s, American English, reedy and worn, slightly querulous. Persistent and no-nonsense, with a thin edge of anxiety beneath the bluntness — she can ill afford to lose what little she is owed."
    voices:
      voxalta: voices/old-woman.vox
  - character: MAN
    episodes: [3]
    voiceDescription: "Landlord collecting back rent"
    voicePrompt: "A male voice in his 40s-50s, American English, flat and transactional. Dry and impatient, low energy clipped delivery — the voice of someone who has heard every excuse and believes none of them."
    voices:
      voxalta: voices/man.vox
  - character: TOWNSPERSON
    episodes: [3]
    voiceDescription: "Dismissive Toledo street figure"
    voicePrompt: "A middle-aged American male voice, clipped and dismissive in tone. Slightly nasal and self-righteous, the voice of someone comfortable enough to look down on others. Short, flat delivery with no warmth."
    voices:
      voxalta: voices/townsperson.vox
  - character: TOWN CRIER
    episodes: [3]
    voiceDescription: "Civic official reading decree"
    voicePrompt: "A commanding American male voice, projecting clearly and loudly as if addressing a crowd in an open square. Officious and detached, with a practiced, theatrical formality — no emotion, just the cold authority of the state."
    voices:
      voxalta: voices/town-crier.vox
  - character: VOICES
    episodes: [5]
    voiceDescription: "Overlapping congregation reactions"
    voicePrompt: "Two distinct American voices briefly overlapping: one higher, frightened female voice calling for divine help, and one lower male voice delivering a harsh judgment — together they should sound like the unguarded, instinctive reactions of a crowd caught between fear and self-righteousness."
    voices:
      voxalta: voices/voices.vox
  # ── NON-SPEAKING / BACKGROUND ──────────────────────────────────
  - character: FRIAR
    episodes: [4]
    voiceDescription: "Fourth master — silent comic figure, no dialogue"
  - character: VEILED WOMEN
    episodes: [3]
    voiceDescription: "Background — no dialogue"
  - character: VILLAGERS
    episodes: [5]
    voiceDescription: "Background crowd — no dialogue"
  - character: STABLE HANDS
    episodes: [1]
    voiceDescription: "Background — no dialogue"
  - character: SUPPLICANTS
    episodes: [1]
    voiceDescription: "Background — no dialogue"
---
