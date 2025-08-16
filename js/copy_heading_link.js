document.addEventListener("DOMContentLoaded", () => {
  const headings = document.querySelectorAll(
    "h1[id], h2[id], h3[id], h4[id], h5[id], h6[id]",
  );

  headings.forEach((heading) => {
    const link = document.createElement("a");
    link.href = `#${heading.id}`;
    link.className = "copy-heading-link-button";
    link.innerHTML =
      '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4"><path stroke-linecap="round" stroke-linejoin="round" d="M13.19 8.688a4.5 4.5 0 011.242 7.244l-4.5 4.5a4.5 4.5 0 01-6.364-6.364l1.757-1.757m13.35-.622l1.757-1.757a4.5 4.5 0 00-6.364-6.364l-4.5 4.5a4.5 4.5 0 001.242 7.244" /></svg>';

    const tooltip = document.createElement("span");
    tooltip.className = "copy-heading-link-tooltip";
    tooltip.textContent = "Copy link";
    link.appendChild(tooltip);

    link.addEventListener("click", (event) => {
      event.preventDefault();
      const url = new URL(link.href, window.location.href).toString();
      navigator.clipboard
        .writeText(url)
        .then(() => {
          tooltip.textContent = "Copied!";
          setTimeout(() => {
            tooltip.textContent = "Copy link";
          }, 2000);
        })
        .catch((err) => {
          console.error("Failed to copy URL: ", err);
          tooltip.textContent = "Failed to copy";
          setTimeout(() => {
            tooltip.textContent = "Copy link";
          }, 2000);
        });
    });

    heading.appendChild(link);
  });
});
