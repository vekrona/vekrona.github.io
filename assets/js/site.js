(function () {
	"use strict";

	var links = document.querySelectorAll("figure.shot a");
	if (!links.length || typeof HTMLDialogElement !== "function") return;

	var dialog = document.createElement("dialog");
	dialog.className = "lightbox";
	dialog.setAttribute("aria-label", "Screenshot preview");

	var closeButton = document.createElement("button");
	closeButton.type = "button";
	closeButton.className = "btn btn-ghost lightbox-close";
	closeButton.textContent = "Close";

	var avifSource = document.createElement("source");
	avifSource.type = "image/avif";

	var big = document.createElement("img");

	var picture = document.createElement("picture");
	picture.append(avifSource, big);

	dialog.append(closeButton, picture);
	document.body.appendChild(dialog);

	links.forEach(function (link) {
		var thumbnail = link.querySelector("img");
		link.setAttribute("aria-haspopup", "dialog");
		link.addEventListener("click", function (event) {
			if (event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
			event.preventDefault();
			big.alt = thumbnail.alt;
			big.src = link.href;
			if (link.dataset.avif) {
				avifSource.srcset = link.dataset.avif;
			}
			dialog.showModal();
		});
	});

	big.addEventListener("error", function () {
		if (!dialog.open) return;
		var failedUrl = big.src;
		dialog.close();
		window.location.assign(failedUrl);
	});

	dialog.addEventListener("close", function () {
		avifSource.removeAttribute("srcset");
		big.removeAttribute("src");
		big.alt = "";
	});

	dialog.addEventListener("click", function () {
		dialog.close();
	});
})();
