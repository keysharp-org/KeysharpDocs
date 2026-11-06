/*
 * Download picker enhancement.
 *
 * The picker is fully working HTML on its own: Windows and macOS cards link to installers, and the
 * Linux card links to installation instructions. Versioned download links are written into the page
 * by scripts/Set-KeysharpVersion.ps1 whenever a Keysharp release appears.
 *
 * This file only tailors the page to the visitor, using information the browser already has:
 *   - marks the card matching their operating system, and
 *   - retargets links to their CPU architecture, choosing between URLs already present in the markup.
 *
 * It makes no network requests, so it cannot be rate limited, blocked or slowed down, and the page
 * behaves correctly with scripting disabled entirely.
 */
(function () {
	'use strict';

	function detect() {
		var ua = navigator.userAgent || '';
		var uaData = navigator.userAgentData;
		var platform = (uaData && uaData.platform) || navigator.platform || '';
		var os = null;

		if (/Win/i.test(platform) || /Windows/i.test(ua)) os = 'windows';
		else if (/Mac/i.test(platform) || /Mac OS X/i.test(ua)) os = 'macos';
		else if (/Linux|X11/i.test(platform) || /Linux/i.test(ua)) os = 'linux';

		// Apple silicon is not reported in the user agent, and every Mac able to run current macOS
		// versions is arm64, so Macs keep the arm64 default in the markup. Elsewhere only an explicit
		// aarch64/arm64 marker moves a link off x64.
		var arch = /aarch64|arm64/i.test(ua) ? 'arm64' : (os === 'macos' ? 'arm64' : 'x64');
		return { os: os, arch: arch };
	}

	function apply() {
		var found = detect();

		// Any link carrying a URL for the detected architecture is pointed at it. Cards and alternate
		// format links use the same attributes, so both are handled here.
		var targeted = document.querySelectorAll('[data-x64],[data-arm64]');
		for (var i = 0; i < targeted.length; i++) {
			var url = targeted[i].getAttribute('data-' + found.arch);
			if (!url) continue;

			targeted[i].href = url;
			// The tooltip names the file being downloaded, so it has to follow the architecture.
			if (targeted[i].title) targeted[i].title = url.substring(url.lastIndexOf('/') + 1);
		}

		// Stamping every card, not just the matched one, is what lets the observer below tell "not done
		// yet" from "done, and this platform simply is not the visitor's".
		var cards = document.querySelectorAll('.dl-card');
		for (var c = 0; c < cards.length; c++)
			cards[c].setAttribute('data-dl-applied', '1');

		if (!found.os) return;

		var card = document.querySelector('.dl-card[data-os="' + found.os + '"]');
		if (!card) return;

		card.setAttribute('aria-current', 'true');
		var mark = card.querySelector('.dl-detected');
		if (mark && mark.textContent !== 'Your system') mark.textContent = 'Your system';
	}

	// The documentation shell may relocate a page's content into another document after this runs, which
	// would drop the changes above. Re-applying whenever an unstamped card appears covers that. The stamp
	// is an attribute, and only childList is observed, so the observer cannot be triggered by its own work.
	function watch() {
		apply();

		if (!window.MutationObserver) return;

		var mo = new MutationObserver(function () {
			if (document.querySelector('.dl-card:not([data-dl-applied])')) apply();
		});
		mo.observe(document.documentElement, { childList: true, subtree: true });
		setTimeout(function () { mo.disconnect(); }, 15000);
	}

	if (document.readyState === 'loading')
		document.addEventListener('DOMContentLoaded', watch);
	else
		watch();
})();
