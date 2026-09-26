/*
 * markless_ocr.js — reading a page of student work in a browser, on the
 * teacher's own machine, so the name can be blacked out before the page is
 * sent anywhere.
 *
 * Everything here is served from our own origin. Same call as pdf.js in
 * index.html: schools block CDNs, and a third-party script that parses a
 * page of a child's work is a dependency worth not having. Vendored from
 * tesseract.js 5.1.1, tesseract.js-core 5.1.1 and @tesseract.js-data/eng
 * 4.0.0_best_int — bump them together.
 *
 * Nothing in this file is fetched until Dart asks for it. The engine and the
 * English model are about 7 MB between them, and a teacher who only ever
 * imports a Google Form must not pay for that on app open.
 *
 * The boundary with Dart is window.postMessage carrying the page bytes one
 * way and a single JSON string back — one shape to keep in step instead of
 * an object graph on both sides, and no JS-interop import on the Dart side
 * that a phone build would then have to analyse.
 */
(function () {
  'use strict';

  // Resolved from this script's own URL, not the page's, so the paths still
  // work from inside the blob worker tesseract.js spawns — a blob URL has no
  // useful base of its own.
  var HERE = (document.currentScript && document.currentScript.src) || (self.location.href + 'tesseract/x.js');
  var DIR = HERE.slice(0, HERE.lastIndexOf('/') + 1);

  // Tesseract reads printed text best at roughly 300 dpi. A scan of A4 at
  // that density is about 2500px on its long side; phone photos land near
  // it and screenshots land well under. Upscaling a small image is worth it
  // and downscaling a huge one keeps a class set from taking minutes.
  var TARGET_LONG_EDGE = 2200;
  var MAX_LONG_EDGE = 3000;

  var loaded = null;
  var worker = null;
  // One worker, one page at a time. Two concurrent recognitions on the same
  // worker interleave their results.
  var queue = Promise.resolve();

  function loadScript(src) {
    return new Promise(function (resolve, reject) {
      var el = document.createElement('script');
      el.src = src;
      el.onload = function () { resolve(); };
      el.onerror = function () { reject(new Error('could not load ' + src)); };
      document.head.appendChild(el);
    });
  }

  function load() {
    if (loaded) return loaded;
    loaded = (function () {
      return (self.Tesseract ? Promise.resolve() : loadScript(DIR + 'tesseract.min.js'))
        .then(function () {
          return self.Tesseract.createWorker('eng', 1 /* LSTM only */, {
            workerPath: DIR + 'worker.min.js',
            // A directory, so tesseract.js picks the SIMD build where the
            // browser has SIMD and the plain one where it does not. Both are
            // vendored; neither is a Chrome-only path.
            corePath: DIR,
            langPath: DIR,
            gzip: true,
            // Keeps the traineddata in IndexedDB, so only the first page a
            // teacher ever marks in this browser waits on the download.
            cacheMethod: 'write',
            legacyCore: false,
            legacyLang: false,
          });
        })
        .then(function (w) {
          worker = w;
          return w.setParameters({
            // A whole sheet of paper with a header line and body text.
            tessedit_pageseg_mode: '3',
            // The label we are hunting is printed; punctuation matters,
            // because "Name" without a colon is not a name field.
            preserve_interword_spaces: '1',
          });
        })
        .then(function () { return true; })
        .catch(function (e) {
          // Let a later page try again rather than disabling name hiding for
          // the rest of the session.
          loaded = null;
          worker = null;
          throw e;
        });
    })();
    return loaded;
  }

  function decode(blob) {
    if (self.createImageBitmap) {
      return createImageBitmap(blob);
    }
    return new Promise(function (resolve, reject) {
      var url = URL.createObjectURL(blob);
      var im = new Image();
      im.onload = function () { URL.revokeObjectURL(url); resolve(im); };
      im.onerror = function () { URL.revokeObjectURL(url); reject(new Error('could not decode the page')); };
      im.src = url;
    });
  }

  // Returns { canvas, scale } where scale maps ORIGINAL page pixels to
  // canvas pixels. Every box we hand back is divided by it, because the
  // bytes Dart paints over are the original ones.
  function toCanvas(bitmap) {
    var w = bitmap.width || bitmap.naturalWidth;
    var h = bitmap.height || bitmap.naturalHeight;
    if (!w || !h) throw new Error('the page has no pixels');
    var longEdge = Math.max(w, h);
    var scale = TARGET_LONG_EDGE / longEdge;
    if (longEdge * scale > MAX_LONG_EDGE) scale = MAX_LONG_EDGE / longEdge;
    // Never blow a tiny thumbnail up past 3x; there is no detail to find.
    if (scale > 3) scale = 3;
    var canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(w * scale));
    canvas.height = Math.max(1, Math.round(h * scale));
    var ctx = canvas.getContext('2d');
    // White behind a transparent PNG: Tesseract reads dark on light.
    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    if (bitmap.close) bitmap.close();
    // Grey, not colour. The app's scanner pass sharpens every photo, and the
    // coloured fringes sharpening leaves round printed type made Tesseract
    // drop whole lines — on a clean test page it lost "Name: Ana Lopez"
    // entirely, so the name went up unhidden. The same page in grey reads
    // at 96%. Done by hand rather than with ctx.filter, which older Safari
    // ignores.
    var px = ctx.getImageData(0, 0, canvas.width, canvas.height);
    var d = px.data;
    for (var i = 0; i < d.length; i += 4) {
      var g = (0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2]) | 0;
      d[i] = d[i + 1] = d[i + 2] = g;
    }
    ctx.putImageData(px, 0, 0);
    return { canvas: canvas, scale: canvas.width / w };
  }

  function flatten(data, scale) {
    var words = [];
    var lineId = 0;
    var blocks = (data && data.blocks) || [];
    for (var b = 0; b < blocks.length; b++) {
      var paras = blocks[b].paragraphs || [];
      for (var p = 0; p < paras.length; p++) {
        var lines = paras[p].lines || [];
        for (var l = 0; l < lines.length; l++) {
          var ws = lines[l].words || [];
          for (var i = 0; i < ws.length; i++) {
            var box = ws[i].bbox || {};
            words.push({
              t: ws[i].text || '',
              c: typeof ws[i].confidence === 'number' ? ws[i].confidence : 0,
              l: lineId,
              x0: box.x0 / scale,
              y0: box.y0 / scale,
              x1: box.x1 / scale,
              y1: box.y1 / scale,
            });
          }
          lineId++;
        }
      }
    }
    return words;
  }

  function read(blob) {
    var run = queue.then(function () {
      return load()
        .then(function () { return decode(blob); })
        .then(function (bitmap) {
          var prepared = toCanvas(bitmap);
          return worker
            .recognize(prepared.canvas, {}, { blocks: true })
            .then(function (res) {
              return JSON.stringify({ words: flatten(res.data, prepared.scale) });
            });
        })
        .catch(function (e) {
          // An empty reading is the honest answer: Dart turns it into "no
          // name was hidden on this page" rather than a silent success.
          if (self.console) console.warn('markless_ocr: ' + (e && e.message ? e.message : e));
          return JSON.stringify({ words: [] });
        });
    });
    // Keep the chain alive whatever happens to this page.
    queue = run.then(function () {}, function () {});
    return run;
  }

  var CHANNEL = 'markless.ocr';

  function reply(id, body) {
    var out = { channel: CHANNEL, dir: 'reply', id: id };
    for (var k in body) out[k] = body[k];
    self.postMessage(out, self.location.origin);
  }

  self.addEventListener('message', function (event) {
    // Only this page talks to this reader. There are no iframes in the app,
    // and a page of a child's work is not something to OCR on anyone else's
    // say-so.
    if (event.source !== self) return;
    var msg = event.data;
    if (!msg || typeof msg !== 'object') return;
    if (msg.channel !== CHANNEL || msg.dir !== 'ask') return;

    if (msg.op === 'load') {
      load().then(
        function () { reply(msg.id, { ok: true }); },
        function (e) { reply(msg.id, { ok: false, error: String(e && e.message ? e.message : e) }); }
      );
      return;
    }
    if (msg.op === 'read') {
      read(new Blob([msg.bytes])).then(function (json) { reply(msg.id, { json: json }); });
    }
  });

  // Still exposed for the harness and for anyone debugging in a console; the
  // app itself only ever uses the message channel above.
  self.marklessOcr = { load: load, read: read };
})();
