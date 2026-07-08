// SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors
//
// SPDX-License-Identifier: EPL-2.0

// Verovio WASM module — embedded (no external fetch required).
import createVerovioModule from 'verovio/wasm-hum';
import { VerovioToolkit } from 'verovio/esm';

// Singleton — shared across all VerovioRenderer hook instances on the page.
let _module   = null;
let _moduleP  = null;

async function ensureModule() {
  if (_module) return _module;
  if (!_moduleP) _moduleP = createVerovioModule().then(m => { _module = m; return m; });
  return _moduleP;
}

// VerovioRenderer hook — attach to any element with:
//   phx-hook="VerovioRenderer"
//   data-render-event="render_musicxml_session"   (or _corpus)
//   phx-update="ignore"
//
// BEAM sends push_event(socket, "render_musicxml_session", %{xml: xml_string})
// → hook renders MusicXML → SVG injected in the element.
const VerovioRenderer = {
  async mounted() {
    const mod = await ensureModule();
    this.toolkit = new VerovioToolkit(mod);
    this.toolkit.setOptions({
      pageHeight:       2970,
      pageWidth:        2100,
      adjustPageHeight: true,
      scale:            45,
      svgViewBox:       true,
      svgBoundingBoxes: true,
    });

    const eventName = this.el.dataset.renderEvent || 'render_musicxml';
    this.handleEvent(eventName, ({ xml }) => this._render(xml));
  },

  _render(xml) {
    if (!this.toolkit) return;
    const ph = this.el.querySelector('.verovio-placeholder');
    if (ph) ph.style.display = 'none';

    const svg = this.toolkit.renderData(xml, {});
    const old = this.el.querySelector('svg');
    if (old) old.remove();
    this.el.insertAdjacentHTML('beforeend', svg);

    this.el.querySelectorAll('g.note').forEach(el => {
      el.style.cursor = 'pointer';
      el.addEventListener('click', () => {
        this.pushEvent('notation_note_click', { note_id: el.getAttribute('id') });
      });
    });
  },
};

export default VerovioRenderer;
