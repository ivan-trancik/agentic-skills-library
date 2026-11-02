---
name: ask-gemini
description: Have Gemini 4 Argon watch a video, listen to audio or give an independent second opinion on a decision that is costly to reverse, or write the user a prompt for searching Gmail and Drive or asking a Gemini Notebook. Use when the user asks for Gemini or Argon, or agrees when you offer it, since every run sends files to Google.
---

Gemini 4 Argon takes the jobs Claude and Codex can't do, or shouldn't judge alone; planning, coding and reviews stay with them. For video and audio, and for second opinions, Argon runs headless through `agy`, the Antigravity CLI, on the user's Google AI Pro plan. For Gmail, Drive and a Gemini Notebook, it runs in Google's own apps, so you write the prompt and the user runs it.

Use this skill only when the user asks for Gemini or Argon, or agrees when you offer it: every run sends the brief and its files to Google. Offer it when a task needs a video or audio file understood, or before a decision that would be costly to reverse.

`${CLAUDE_SKILL_DIR}` in the commands below stands for this skill's folder, the one that holds this file.

Give each job a short name, such as `squat-depth` or `queue-choice`. Its files go in `.local/gemini/`.

## Running Argon

`ask.sh` copies the files into a throwaway folder and runs Argon there. Argon can read those copies and search the web, and nothing else: every write, command, URL fetch and MCP call is denied, and so is any read of the repository, your notes or the user's files. Run it from the project, in the foreground with a 10-minute timeout; it stops Argon after eight minutes. It needs the network: if you are Codex and your sandbox has no network access, run it outside the sandbox.

```
${CLAUDE_SKILL_DIR}/scripts/ask.sh <--media|--second-opinion> .local/gemini/<name>-brief.md .local/gemini/<name>.md [file ...]
```

It writes the answer only when Argon opened every file and answered. When it fails, tell the user what it printed, such as `agy` not being signed in, the weekly Argon allowance being used up, the deadline, or a file Argon didn't open, and stop. Don't rerun on another model unless the user asks, and never pass off another model's answer as Argon's. When it warns that the answer was cut off, say so as you report it.

## Video and audio

1. Find each file's length with `ffprobe -v error -show_entries format=duration -of csv=p=0 <file>`. Argon's allowance is weekly, so for a file over ten minutes, ask the user whether to cut out the part that matters first: `ffmpeg -v error -ss <start> -to <end> -i <file> -c copy .local/gemini/<name>-part.<extension>`.
2. Write the brief: the user's question, word for word, and what to look or listen for.
3. Run `ask.sh --media` with the brief, the answer and the files. Argon replies with a table of times, what it saw or heard, and what it infers, and lists the moments too fast to judge at its one frame a second.
4. Check every row, and mark it confirmed, contradicted or unchecked:
   - A row about what is on screen: look at a strip of eight frames from a second either side of its time, or of the middle of its range. Take the strip with `ffmpeg -v error -ss <that time minus 1 second> -i <video> -t 2 -vf fps=4,scale=320:-2,tile=4x2 -frames:v 1 .local/gemini/<name>-<m>m<ss>s.jpg`, then read the image.
   - A row about what is heard stays unchecked: neither Claude nor Codex can listen.
5. If the user's question turns on a fast moment, such as a lift, a stride or something that flashes on screen, including one that Argon listed as too fast to judge, slow it down and ask again. Cut the few seconds around it and slow them `<n>` times, without sound: `ffmpeg -v error -ss <start> -to <end> -i <video> -vf 'setpts=<n>*PTS' -an -pix_fmt yuv420p .local/gemini/<name>-slow.mp4`. Argon then sees `<n>` frames for each real second, up to the video's own frame rate. Four times is a good start; very fast motion, such as a bar path, may need eight. The slow part costs `<n>` times its tokens, so keep the cut short.
   - Run `ask.sh --media` on the slow clip with a brief that adds which part of the original it is and how much it is slowed, so that Argon judges speed accordingly.
   - A time `t` in the slow clip is `<start> + t / <n>` in the original. Check the rows against the slow clip as in step 4, and give the user times in the original.
6. Report the table with your marks. Give the user the times of the unchecked rows and of the fast moments, to check for themselves. Then carry on with the task: Argon found the moments, and you analyse them and make any change that follows.

## A second opinion on a costly decision

1. Write your own recommendation and your reasons to `.local/gemini/<name>-own.md` first. Argon never sees it.
2. Write the brief with the raw problem: the decision, the goal, the constraints, the options you know of, and the facts and figures. Leave out your recommendation, your reasoning about the options and which way you lean. Pass the files the decision rests on, such as code, data or documents, but never your plan, notes or analysis.
3. Run `ask.sh --second-opinion` with the brief, the answer and the files.
4. Show the user both recommendations side by side: where they agree, where they differ and why, and anything Argon raised that you had missed. The user decides.

## Gmail and Drive, and a Gemini Notebook

Argon reaches Gmail, Drive and the user's notebooks only in Google's apps, so the user runs these: Gmail and Drive searches in the standalone Gemini app, not in the Gmail or Drive sidebar, and Notebook questions in the notebook.

1. Write the prompt to `.local/gemini/<name>-prompt.md`.
   - For Gmail and Drive: what to find, then "List every match: whether it is an email or a file, the sender or owner, the date, the subject or title, a link, and a short quote of the passage that matters. Inspect every attachment of the matching emails. Don't summarise or draw conclusions."
   - For a Notebook: the question, then "Answer only from this notebook's sources, with a citation for each claim. Say which parts of the question the sources don't answer." A Notebook reads only the transcript of a YouTube source, so for what happens on screen, use the video job instead.
2. Put the prompt on the clipboard with `pbcopy < .local/gemini/<name>-prompt.md`, and for Gmail and Drive open the app with `open -a Gemini`. Tell the user to choose 4 Argon in the model menu, paste the prompt, and paste the answer back to you; thinking set to High uses up the allowance faster.
3. Save the answer to `.local/gemini/<name>.md` and interpret it. Argon found the material; the decisions are yours and the user's.

## Logging each job

When a job is done, log it, so that after a month the log shows whether Argon finds what Claude and Codex miss:

```
${CLAUDE_SKILL_DIR}/scripts/log.sh --job <media|second-opinion|gmail-drive|notebook> --added <yes|no> --corrections <n> --answer .local/gemini/<name>.md
```

`--added` says whether Argon gave you something you didn't have: for video or audio, findings you could use; for a second opinion, a point you had missed. `--corrections` counts its claims that you or the user had to correct; each contradicted row counts as one.
