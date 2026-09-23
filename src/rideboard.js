// Ride board interactions.
//
// The board is server-rendered; this layer only avoids full page reloads. Every
// action is a real form POST, so the board still works with JS disabled — it
// just redirects instead of swapping the fragment.

const ROOT = '[data-board-root]'

const root = () => document.querySelector(ROOT)

// Replace the board in place, preserving scroll positions so dropping a rider
// doesn't jump you back to the top of a long queue.
const swap = html => {
  const current = root()
  if (!current) return

  const scrolls = [...current.querySelectorAll('.overflow-y-auto')].map(el => el.scrollTop)

  const next = new DOMParser().parseFromString(html, 'text/html').querySelector(ROOT)
  if (!next) { window.location.reload(); return }

  current.replaceWith(next)

  const panes = [...next.querySelectorAll('.overflow-y-auto')]
  panes.forEach((el, i) => { if (scrolls[i] != null) el.scrollTop = scrolls[i] })
}

const post = async (action, body) => {
  const response = await fetch(action, {
    method: 'POST',
    headers: { 'X-Requested-With': 'XMLHttpRequest' },
    body,
    credentials: 'same-origin'
  })

  if (!response.ok) {
    const message = await response.text()
    window.alert(message || 'That change could not be saved.')
    return
  }

  swap(await response.text())
}

const submitForm = form => {
  const data = new FormData(form)
  data.set('fragment', '1')
  // The submit button's own name/value is not in FormData when submitted
  // programmatically, but none of the board's buttons carry data.
  return post(form.action, data)
}

// --- forms -----------------------------------------------------------------

document.addEventListener('submit', event => {
  const form = event.target.closest('[data-board-form]')
  if (!form) return

  const confirmable = form.querySelector('[data-confirm]')
  if (confirmable && !window.confirm(confirmable.dataset.confirm)) {
    event.preventDefault()
    return
  }

  event.preventDefault()
  submitForm(form)
})

// "Other — add a new place…" on the member form reveals the inline fields for
// it. The panel sits in the same form, so picking Other and filling it in saves
// the member and creates the place in one press.
const NEW_LOCATION = '__new__'

document.addEventListener('change', event => {
  const select = event.target.closest('[data-location-select]')
  if (!select) return

  const prefix = select.dataset.locationSelect === 'class_location_id'
    ? 'new_class_location'
    : 'new_location'
  const panel = select.form?.querySelector(`[data-new-location="${prefix}"]`)
  if (!panel) return

  const adding = select.value === NEW_LOCATION
  panel.hidden = !adding
  if (adding) panel.querySelector('input')?.focus()
})

// Ordinary forms outside the board — cancelling a date on the schedule, say.
// The board's own handler above swallows its forms and AJAXes them instead;
// this one only confirms, then lets the browser submit normally.
document.addEventListener('submit', event => {
  const form = event.target
  if (!form.matches('form') || form.closest('[data-board-form]')) return

  const confirmable = form.querySelector('[data-confirm]')
  if (confirmable && !window.confirm(confirmable.dataset.confirm)) event.preventDefault()
})

// --- live filter -----------------------------------------------------------

let filterTimer = null

document.addEventListener('input', event => {
  const input = event.target.closest('[data-board-search] input[name="q"]')
  if (!input) return

  clearTimeout(filterTimer)
  filterTimer = setTimeout(async () => {
    const form = input.closest('form')
    const url = `${form.action}?${new URLSearchParams(new FormData(form))}`
    const response = await fetch(url, {
      headers: { 'X-Requested-With': 'XMLHttpRequest' },
      credentials: 'same-origin'
    })
    if (!response.ok) return

    const caret = input.selectionStart
    swap(await response.text())

    const next = document.querySelector('[data-board-search] input[name="q"]')
    if (next) {
      next.focus()
      next.setSelectionRange(caret, caret)
    }
  }, 200)
})

// --- drag and drop ---------------------------------------------------------

let dragging = null

document.addEventListener('dragstart', event => {
  const card = event.target.closest('[data-draggable-rider="true"]')
  if (!card) return

  dragging = card.dataset.rideId
  event.dataTransfer.setData('text/plain', dragging)
  event.dataTransfer.effectAllowed = 'move'
  card.classList.add('board-dragging')
})

document.addEventListener('dragend', event => {
  const card = event.target.closest('[data-draggable-rider="true"]')
  if (card) card.classList.remove('board-dragging')
  dragging = null
  document.querySelectorAll('.board-drop-active').forEach(el => el.classList.remove('board-drop-active'))
})

document.addEventListener('dragover', event => {
  const zone = event.target.closest('[data-drop-zone]')
  if (!zone || !dragging) return

  event.preventDefault()
  event.dataTransfer.dropEffect = 'move'
  zone.classList.add('board-drop-active')
})

document.addEventListener('dragleave', event => {
  const zone = event.target.closest('[data-drop-zone]')
  if (!zone) return
  // Ignore moves between children of the same zone.
  if (zone.contains(event.relatedTarget)) return
  zone.classList.remove('board-drop-active')
})

document.addEventListener('drop', event => {
  const zone = event.target.closest('[data-drop-zone]')
  if (!zone) return

  event.preventDefault()
  zone.classList.remove('board-drop-active')

  const rideId = event.dataTransfer.getData('text/plain') || dragging
  if (!rideId) return

  const board = root()
  if (!board || board.dataset.readonly === 'true') return

  const body = new FormData()
  body.set('ride_id', rideId)
  body.set('driver_ride_id', zone.dataset.driverRideId || '')
  body.set('fragment', '1')

  const search = document.querySelector('[data-board-search] input[name="q"]')
  if (search && search.value) body.set('q', search.value)

  post(`${board.dataset.endpoint}/assign`, body)
})

// --- driver tags -----------------------------------------------------------
//
// The chips on the member page toggle a value in the comma-separated tag box
// rather than being their own field, so there is exactly one place the tags
// live and typing a brand new one still works.
document.addEventListener('click', event => {
  const chip = event.target.closest('[data-tag-chip]')
  if (!chip) return

  const box = chip.closest('form')?.querySelector('[data-tag-input]')
  if (!box) return

  const tag = chip.dataset.tagChip
  const tags = box.value.split(',').map(t => t.trim()).filter(Boolean)
  const at = tags.findIndex(t => t.toLowerCase() === tag.toLowerCase())

  if (at === -1) tags.push(tag)
  else tags.splice(at, 1)

  box.value = tags.join(', ')
  chip.dispatchEvent(new CustomEvent('tag:toggled', { bubbles: true }))
  // Re-style without a round trip.
  chip.classList.toggle('bg-accent-tint', at === -1)
  chip.classList.toggle('text-accent', at === -1)
  chip.classList.toggle('border-accent/30', at === -1)
  chip.classList.toggle('text-ink/60', at !== -1)
})

// --- background optimize -----------------------------------------------------
//
// With jobs on, Optimize returns at once and the board shows "Optimizing…"
// (data-board-poll). Re-fetch the board fragment until that marker is gone,
// i.e. until the job has finished and the result is on the board.
setInterval(async () => {
  const board = root()
  if (!board || !board.querySelector('[data-board-poll]')) return

  const url = new URL(window.location.href)
  url.searchParams.set('fragment', '1')
  const response = await fetch(url, { headers: { 'X-Requested-With': 'XMLHttpRequest' }, credentials: 'same-origin' })
  if (response.ok) swap(await response.text())
}, 2000)
