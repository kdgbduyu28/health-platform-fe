/// The few browser features the apps use directly: links out, downloads,
/// picking a file, and printing. The apps are web-only, but every function
/// here checks for a browser first so the logic around them can be tested in
/// Node.

export function inBrowser(): boolean {
  return typeof window !== 'undefined' && typeof document !== 'undefined';
}

/// Opens [url] in a new tab (or the app that handles it, for webcal://).
export function openExternal(url: string): void {
  if (!inBrowser()) return;
  // webcal:// hands off to the calendar app; a new tab would stay blank.
  if (url.startsWith('webcal:')) {
    window.location.href = url;
  } else {
    window.open(url, '_blank', 'noopener');
  }
}

/// Hands [contents] to the browser as a file download named [fileName]. On
/// iPhone, a text/calendar file opens straight into "Add to Calendar".
export function downloadTextFile(fileName: string, mimeType: string, contents: string): void {
  if (!inBrowser()) return;
  const blob = new Blob([contents], { type: `${mimeType};charset=utf-8` });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = fileName;
  document.body.append(a);
  a.click();
  a.remove();
  // Give the browser a moment to start the download before the URL goes.
  setTimeout(() => URL.revokeObjectURL(url), 5000);
}

/// Where the app is served from, for links back into it. Null outside a
/// browser.
export function appOrigin(): string | null {
  if (!inBrowser()) return null;
  const { protocol, origin } = window.location;
  return protocol === 'http:' || protocol === 'https:' ? origin : null;
}

/// A file the person picked, as text.
export type PickedTextFile = { name: string; text: string };

/// Asks the browser for one file (by default a CSV) and reads it. Null if
/// they cancel, and always outside a browser.
export function pickTextFile(accept = '.csv,text/csv'): Promise<PickedTextFile | null> {
  if (!inBrowser()) return Promise.resolve(null);
  return new Promise((resolve, reject) => {
    let settled = false;
    const finish = (value: PickedTextFile | null) => {
      if (!settled) {
        settled = true;
        resolve(value);
      }
    };
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = accept;
    input.addEventListener('change', async () => {
      const file = input.files?.item(0);
      if (!file) return finish(null);
      try {
        const buffer = await file.arrayBuffer();
        finish({ name: file.name, text: decodeTextFile(new Uint8Array(buffer)) });
      } catch (e) {
        if (!settled) {
          settled = true;
          reject(e);
        }
      }
    });
    // Closing the dialog without a file (browsers that report it).
    input.addEventListener('cancel', () => finish(null));
    input.click();
  });
}

/// A spreadsheet's bytes as text. UTF-8 normally; Excel on Windows still
/// saves "CSV" in the old Western encoding, where "Peña" is not valid UTF-8,
/// so that falls back to Latin-1 instead of turning the ñ into �.
export function decodeTextFile(bytes: Uint8Array): string {
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    return new TextDecoder('latin1').decode(bytes);
  }
}

let printFrame: HTMLIFrameElement | null = null;

/// Opens the browser's print dialog on [html], a whole page, where the user
/// prints it or saves it as a PDF. The page's `<title>` is the name offered
/// for the PDF. Relative URLs in it resolve against the app's base URL.
///
/// A hidden frame rather than a new tab: popup blockers leave it alone, and
/// the app stays where it was behind the dialog. False outside a browser.
export function printHtml(html: string): boolean {
  if (!inBrowser()) return false;
  printFrame?.remove();
  const page = html.replace('<head>', `<head><base href="${document.baseURI}">`);

  const frame = document.createElement('iframe');
  frame.setAttribute('aria-hidden', 'true');
  Object.assign(frame.style, { position: 'fixed', right: '0', bottom: '0', width: '0', height: '0', border: '0' });
  printFrame = frame;

  frame.onload = () => {
    const win = frame.contentWindow;
    if (!win) return;
    // Some browsers name the PDF after the app's tab, not the frame.
    const title = document.title;
    const printTitle = frame.contentDocument?.title ?? '';
    if (printTitle) document.title = printTitle;
    const done = () => {
      document.title = title;
    };
    win.addEventListener('afterprint', done);
    win.focus();
    win.print();
    // Where print() does not block, afterprint restores the title; where it
    // does, it has returned by now. Either way the frame stays until the
    // next print, as Safari still reads it after print() returns.
    setTimeout(done, 2000);
  };

  frame.srcdoc = page;
  document.body.append(frame);
  return true;
}

/// Copies [text] to the clipboard. False when the browser refused.
export async function copyText(text: string): Promise<boolean> {
  if (!inBrowser() || !navigator.clipboard) return false;
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    return false;
  }
}
