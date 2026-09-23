// "Browse all emoji" on the sign-up page.
//
// The server has always accepted any emoji in the text box beside this; the
// picker existed to make one findable without knowing its name. So this writes
// into that same text box rather than inventing a second way to submit —
// `POST /signups/:id/options` reads `emoji` and lets it win over the radio
// grid, which is exactly the behaviour a picked emoji wants.
//
// The catalogue is ~1,900 entries and is fetched once, on first open. Rendering
// all of them at once is what makes the grid slow, not the parsing, so only the
// first LIMIT matches are drawn and the count says how many were left out.

const LIMIT = 240

let catalogue = null
let loading = null

const load = async () => {
  if (catalogue) return catalogue
  // One request even if the details is opened and closed repeatedly.
  // The app may be mounted under a prefix (abidepurdue.com/abidebot); the
  // layout writes it on <body> so nothing here hardcodes the root.
  const root = document.body.dataset.root || ''
  loading ||= fetch(`${root}/emoji.json`, { credentials: 'same-origin' })
    .then(r => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
    .then(data => (catalogue = data))
  return loading
}

// A custom emoji has no character to draw, so it carries an image URL instead.
const face = entry =>
  entry.u
    ? `<img src="${entry.u}" alt="" loading="lazy" class="w-[22px] h-[22px] object-contain">`
    : entry.c

const button = entry => {
  const el = document.createElement('button')
  el.type = 'button'
  // `v` is what gets submitted when it differs from what is shown — a custom
  // emoji displays as an image but submits as <:name:id>.
  el.dataset.emojiValue = entry.v || entry.c
  el.title = `:${entry.n}:`
  el.className =
    'flex items-center justify-center w-9 h-9 text-[19px] leading-none rounded-lg ' +
    'border border-line bg-surface hover:bg-surface-sunk cursor-pointer'
  el.innerHTML = face(entry)
  return el
}

const render = (picker, query) => {
  const results = picker.querySelector('[data-emoji-results]')
  const status = picker.querySelector('[data-emoji-status]')
  const needle = query.trim().toLowerCase()

  const matches = needle
    ? catalogue.filter(e => e.k.includes(needle) || e.n.includes(needle) || e.c === needle)
    : catalogue

  results.replaceChildren(...matches.slice(0, LIMIT).map(button))

  if (matches.length === 0) {
    status.textContent = `Nothing matches "${query.trim()}". You can still type it in the box below.`
  } else if (matches.length > LIMIT) {
    status.textContent = `Showing ${LIMIT} of ${matches.length} — keep typing to narrow it down.`
  } else {
    status.textContent = `${matches.length} emoji`
  }
}

const open = async picker => {
  if (picker.dataset.emojiReady) return

  const status = picker.querySelector('[data-emoji-status]')
  try {
    await load()
  } catch (err) {
    status.textContent = 'Could not load the emoji list. Typing one in the box below still works.'
    console.error('[emoji] catalogue failed:', err)
    return
  }

  picker.dataset.emojiReady = 'true'
  render(picker, '')
}

document.addEventListener('toggle', event => {
  const picker = event.target.closest('[data-emoji-picker]')
  if (picker && picker.open) open(picker)
}, true) // `toggle` does not bubble

document.addEventListener('input', event => {
  const box = event.target.closest('[data-emoji-search]')
  if (!box || !catalogue) return

  render(box.closest('[data-emoji-picker]'), box.value)
})

// Picking writes into the text field the form already submits, so the choice is
// visible and editable rather than hidden state.
document.addEventListener('click', event => {
  const choice = event.target.closest('[data-emoji-value]')
  if (!choice) return

  const form = choice.closest('form')
  const box = form?.querySelector('input[name="emoji"]')
  if (!box) return

  box.value = choice.dataset.emojiValue
  // Clear the radio grid so the two controls cannot disagree about what is
  // selected — the server prefers the text box, and now the page says so too.
  form.querySelectorAll('input[name="emoji_pick"]:checked').forEach(radio => { radio.checked = false })

  const picker = choice.closest('[data-emoji-picker]')
  if (picker) picker.open = false
  box.focus()
})
