// The ride board's route map.
//
// Leaflet over OpenStreetMap tiles, because it needs no account, no token and
// no card on file. The tile source is read from the container, so pointing this
// at Mapbox is a config change rather than a code change — see
// `Abid.map_tiles` in config/environment.rb.
//
// The server still computes the routes; this only draws them on a basemap. It
// reads a GeoJSON-ish payload off the element rather than fetching, so there is
// one request for the page and none for the data.
import L from 'leaflet'

const SELECTOR = '[data-route-map]'

// Leaflet resolves its marker images relative to the CSS, and we copied the
// stylesheet rather than bundling it. We draw our own markers, so the default
// icon is never used — but Leaflet still probes for it without this.
delete L.Icon.Default.prototype._getIconUrl
L.Icon.Default.mergeOptions({
  iconUrl: '/css/images/marker-icon.png',
  iconRetinaUrl: '/css/images/marker-icon-2x.png',
  shadowUrl: '/css/images/marker-shadow.png'
})

const readJSON = (el, name) => {
  try {
    return JSON.parse(el.dataset[name] || 'null')
  } catch (err) {
    console.error(`[ridemap] could not read ${name}:`, err)
    return null
  }
}

// A numbered pin in the route's own colour. Built as a div so it picks up the
// same CSS custom properties the rest of the page uses, which is what makes
// dark mode work without a second palette here.
const stopIcon = (colour, label) =>
  L.divIcon({
    className: 'route-pin',
    html: `<span style="background:${colour}">${label}</span>`,
    iconSize: [22, 22],
    iconAnchor: [11, 11]
  })

const venueIcon = () =>
  L.divIcon({
    className: 'route-venue',
    html: '<span></span>',
    iconSize: [18, 18],
    iconAnchor: [9, 9]
  })

// Someone who still needs a seat. Hollow and dashed so it reads as "not yet in
// a car" next to the solid numbered pins — shape, not just colour.
const waitingIcon = () =>
  L.divIcon({
    className: 'route-waiting',
    html: '<span></span>',
    iconSize: [18, 18],
    iconAnchor: [9, 9]
  })

const draw = el => {
  const routes = readJSON(el, 'routes') || []
  const venue = readJSON(el, 'venue')
  const waiting = readJSON(el, 'waiting') || []
  const tiles = el.dataset.tiles
  const attribution = el.dataset.attribution || ''

  const map = L.map(el, { scrollWheelZoom: false, zoomControl: true })
  L.tileLayer(tiles, { attribution, maxZoom: 19 }).addTo(map)

  const bounds = []

  routes.forEach(route => {
    const line = route.stops.map(s => [s.lat, s.lon])
    if (venue) line.push([venue.lat, venue.lon])

    if (line.length > 1) {
      L.polyline(line, { color: route.colour, weight: 3, opacity: 0.85 }).addTo(map)
    }

    route.stops.forEach((stop, i) => {
      L.marker([stop.lat, stop.lon], { icon: stopIcon(route.colour, i + 1), title: stop.name })
        .addTo(map)
        .bindPopup(`<strong>${stop.name}</strong><br>${stop.label || ''}<br><em>${route.driver}</em>`)
      bounds.push([stop.lat, stop.lon])
    })
  })

  // Before anyone is seated these are the only pins there are, and they are the
  // reason to look at this page at all: four people on one street is what tells
  // you which car they belong in.
  waiting.forEach(person => {
    L.marker([person.lat, person.lon], { icon: waitingIcon(), title: person.name })
      .addTo(map)
      .bindPopup(`<strong>${person.name}</strong><br>${person.label || ''}<br><em>waiting for a ride</em>`)
    bounds.push([person.lat, person.lon])
  })

  if (venue) {
    L.marker([venue.lat, venue.lon], { icon: venueIcon(), title: venue.name })
      .addTo(map)
      .bindPopup(`<strong>${venue.name}</strong>`)
    bounds.push([venue.lat, venue.lon])
  }

  if (bounds.length === 0) return
  // A single point has no extent, so fitBounds would zoom to maximum.
  if (bounds.length === 1) map.setView(bounds[0], 14)
  else map.fitBounds(bounds, { padding: [40, 40] })
}

const init = () => document.querySelectorAll(SELECTOR).forEach(draw)

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init)
} else {
  init()
}
