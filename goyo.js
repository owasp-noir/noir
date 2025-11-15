function debounce(func, wait) {
  var timeout;

  return function () {
    var context = this;
    var args = arguments;
    clearTimeout(timeout);

    timeout = setTimeout(function () {
      timeout = null;
      func.apply(context, args);
    }, wait);
  };
}

function makeTeaser(body, terms) {
  var TERM_WEIGHT = 40;
  var NORMAL_WORD_WEIGHT = 2;
  var FIRST_WORD_WEIGHT = 8;
  var TEASER_MAX_WORDS = 30;

  var stemmedTerms = terms.map(function (w) {
    return w.toLowerCase(); // Removed stemming for Fuse.js compatibility
  });
  var termFound = false;
  var index = 0;
  var weighted = []; // contains elements of ["word", weight, index_in_document]

  var sentences = body.toLowerCase().split(". ");

  for (var i in sentences) {
    var words = sentences[i].split(" ");
    var value = FIRST_WORD_WEIGHT;

    for (var j in words) {
      var word = words[j];

      if (word.length > 0) {
        for (var k in stemmedTerms) {
          if (word.toLowerCase().startsWith(stemmedTerms[k])) {
            value = TERM_WEIGHT;
            termFound = true;
          }
        }
        weighted.push([word, value, index]);
        value = NORMAL_WORD_WEIGHT;
      }

      index += word.length;
      index += 1; // ' ' or '.' if last word in sentence
    }

    index += 1; // because we split at a two-char boundary '. '
  }

  if (weighted.length === 0) {
    return body;
  }

  var windowWeights = [];
  var windowSize = Math.min(weighted.length, TEASER_MAX_WORDS);
  var curSum = 0;
  for (var i = 0; i < windowSize; i++) {
    curSum += weighted[i][1];
  }
  windowWeights.push(curSum);

  for (var i = 0; i < weighted.length - windowSize; i++) {
    curSum -= weighted[i][1];
    curSum += weighted[i + windowSize][1];
    windowWeights.push(curSum);
  }

  var maxSumIndex = 0;
  if (termFound) {
    var maxFound = 0;
    for (var i = windowWeights.length - 1; i >= 0; i--) {
      if (windowWeights[i] > maxFound) {
        maxFound = windowWeights[i];
        maxSumIndex = i;
      }
    }
  }

  var teaser = [];
  var startIndex = weighted[maxSumIndex][2];
  for (var i = maxSumIndex; i < maxSumIndex + windowSize; i++) {
    var word = weighted[i];
    if (startIndex < word[2]) {
      teaser.push(body.substring(startIndex, word[2]));
      startIndex = word[2];
    }

    if (word[1] === TERM_WEIGHT) {
      teaser.push("<b>");
    }
    startIndex = word[2] + word[0].length;
    teaser.push(body.substring(word[2], startIndex));

    if (word[1] === TERM_WEIGHT) {
      teaser.push("</b>");
    }
  }
  teaser.push("…");
  return teaser.join("");
}

function formatSearchResultItem(item, terms) {
  var li = document.createElement("li");
  li.className = "search-result-item";
  li.innerHTML = `
    <a href="${item.item.id}" class="search-result-link block px-4 py-3 rounded-lg hover:bg-base-200/50 transition-colors duration-150 border-gray-500/15">
      <div class="flex items-start gap-3">
        <div class="search-result-icon flex-shrink-0 mt-1">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-primary/70" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
          </svg>
        </div>
        <div class="flex-1 min-w-0">
          <div class="search-result-title font-semibold text-sm text-base-content mb-1">${item.item.title}</div>
          <div class="search-result-excerpt text-xs text-base-content/60 line-clamp-2">${makeTeaser(item.item.body, terms)}</div>
        </div>
        <div class="search-result-arrow flex-shrink-0 opacity-0 transition-opacity duration-150">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-base-content/40" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
          </svg>
        </div>
      </div>
    </a>
  `;

  // Add hover effect for the arrow
  var link = li.querySelector(".search-result-link");
  var arrow = li.querySelector(".search-result-arrow");
  link.addEventListener("mouseenter", function () {
    arrow.style.opacity = "1";
  });
  link.addEventListener("mouseleave", function () {
    arrow.style.opacity = "0";
  });

  return li;
}

function initSearch() {
  var $searchInput = document.getElementById("search");
  if (!$searchInput) {
    return;
  }

  var $searchResultsContainer = document.querySelector(
    ".search-results-container",
  );
  var $searchResultsHeader = document.querySelector(".search-results__header");
  var $searchResultsItems = document.querySelector(".search-results__items");
  var MAX_ITEMS = 10;
  var selectedIndex = -1;

  var options = {
    keys: [
      { name: "title", weight: 2 },
      { name: "body", weight: 1 },
      { name: "tags", weight: 1 },
    ],
    includeScore: true,
    ignoreLocation: true,
    threshold: 0.4, // Adjust as needed for search sensitivity
  };
  var currentTerm = "";
  var documents = Object.values(window.searchIndex.documentStore.docs);
  var fuse = new Fuse(documents, options);

  function updateSelectedResult() {
    var items = $searchResultsItems.querySelectorAll(".search-result-item");
    items.forEach(function (item, index) {
      var link = item.querySelector(".search-result-link");
      if (index === selectedIndex) {
        link.classList.add("border");
      } else {
        link.classList.remove("border");
      }
    });

    // Scroll selected item into view
    if (selectedIndex >= 0 && items[selectedIndex]) {
      items[selectedIndex].scrollIntoView({
        block: "nearest",
        behavior: "smooth",
      });
    }
  }

  $searchInput.addEventListener(
    "keyup",
    debounce(function () {
      var term = $searchInput.value.trim();
      if (term === currentTerm || !fuse) {
        return;
      }
      $searchResultsItems.innerHTML = "";
      $searchResultsHeader.innerHTML = "";
      selectedIndex = -1;

      if (term === "") {
        currentTerm = "";
        return;
      }

      var results = fuse.search(term).filter(function (r) {
        return r.item.body !== "";
      });

      if (results.length === 0) {
        $searchResultsHeader.innerHTML = `<span class="text-base-content/60">No results found for <strong class="text-base-content">"${term}"</strong></span>`;
        return;
      }

      currentTerm = term;
      $searchResultsHeader.innerHTML = `<span class="text-base-content/60">${results.length} result${results.length === 1 ? "" : "s"} for <strong class="text-base-content">"${term}"</strong></span>`;
      for (var i = 0; i < Math.min(results.length, MAX_ITEMS); i++) {
        if (!results[i].item.body) {
          continue;
        }
        $searchResultsItems.appendChild(
          formatSearchResultItem(results[i], term.split(" ")),
        );
      }
    }, 150),
  );

  // Focus search input when modal is opened
  var searchModal = document.getElementById("search-modal");
  var modalBackdrop = document.querySelector(".modal");

  if (searchModal) {
    searchModal.addEventListener("change", function () {
      if (this.checked) {
        setTimeout(function () {
          $searchInput.focus();
        }, 100);
      } else {
        // Clear search when modal is closed
        $searchInput.value = "";
        $searchResultsItems.innerHTML = "";
        $searchResultsHeader.innerHTML = "";
        currentTerm = "";
        selectedIndex = -1;
      }
    });
  }

  // Handle click outside modal to close it
  if (modalBackdrop) {
    modalBackdrop.addEventListener("click", function (e) {
      // Close modal if clicking on the backdrop (not on modal-box)
      if (e.target === modalBackdrop && searchModal.checked) {
        searchModal.checked = false;
      }
    });
  }

  // Handle keyboard navigation
  $searchInput.addEventListener("keydown", function (e) {
    var items = $searchResultsItems.querySelectorAll(".search-result-item");

    if (e.key === "Escape") {
      searchModal.checked = false;
      return;
    }

    if (items.length === 0) {
      return;
    }

    if (e.key === "ArrowDown") {
      e.preventDefault();
      selectedIndex = Math.min(selectedIndex + 1, items.length - 1);
      updateSelectedResult();
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      selectedIndex = Math.max(selectedIndex - 1, -1);
      updateSelectedResult();
    } else if (e.key === "Enter" && selectedIndex >= 0) {
      e.preventDefault();
      var link = items[selectedIndex].querySelector(".search-result-link");
      if (link) {
        window.location.href = link.getAttribute("href");
      }
    }
  });
}

function initTheme() {
  var themeController = document.querySelector(".theme-controller");
  if (!themeController) {
    return;
  }

  // Theme mapping - maps user-friendly names to actual DaisyUI theme names
  var themeMapping = {
    "goyo-dark": "night",
    "goyo-light": "lofi",
  };

  // Reverse mapping for checking current theme
  var reverseThemeMapping = {
    night: "goyo-dark",
    lofi: "goyo-light",
  };

  var fallbackTheme =
    window && window.fallbackTheme ? window.fallbackTheme : "goyo-dark";
  var currentUserTheme = localStorage.getItem("theme") || fallbackTheme;

  // Map user theme to actual DaisyUI theme
  var actualTheme = themeMapping[currentUserTheme] || currentUserTheme;
  document.documentElement.setAttribute("data-theme", actualTheme);
  
  // Note: brightness attribute is already set in head.html to prevent FOUC

  // Set checkbox state based on current theme
  themeController.checked = currentUserTheme === "goyo-dark";

  themeController.addEventListener("change", function (e) {
    var userTheme = e.target.checked ? "goyo-dark" : "goyo-light";
    var actualTheme = themeMapping[userTheme];

    document.documentElement.setAttribute("data-theme", actualTheme);
    localStorage.setItem("theme", userTheme); // Store user-friendly name
  });
}

function initToc() {
  const headings = document.querySelectorAll(
    ".prose h1[id], .prose h2[id], .prose h3[id], .prose h4[id], .prose h5[id], .prose h6[id]",
  );
  const tocLinks = document.querySelectorAll(".toc-link");
  const tocDetails = document.querySelectorAll(".toc-details");

  if (headings.length === 0 || tocLinks.length === 0) {
    return; // No ToC or headings on this page
  }

  // Check if TOC should always be expanded
  const tocContainer = document.querySelector(".hidden.lg\\:block");
  const tocExpand = tocContainer && tocContainer.getAttribute("data-toc-expand") === "true";

  let activeId = null;

  const activateLink = (id) => {
    if (activeId === id) return; // Already active, no need to update
    
    activeId = id;
    
    // Remove active class from all links
    tocLinks.forEach((link) => link.classList.remove("active"));
    
    // Only close details if toc_expand is not enabled
    if (!tocExpand) {
      tocDetails.forEach((detail) => (detail.open = false));
    }

    // Match links with href ending in #id (handles both relative and absolute URLs)
    const correspondingLink = document.querySelector(
      `.toc-link[href$="#${id}"]`,
    );

    // Add active class to the current link
    if (correspondingLink) {
      correspondingLink.classList.add("active");
      let parentDetails = correspondingLink.closest("details");
      while (parentDetails) {
        parentDetails.open = true;
        parentDetails = parentDetails.parentElement.closest("details");
      }
    }
  };

  const observerOptions = {
    root: null, // viewport
    rootMargin: "-20% 0px -35% 0px", // Trigger when heading enters the top 20-65% of viewport
    threshold: 0,
  };

  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        const id = entry.target.getAttribute("id");
        if (id) {
          activateLink(id);
        }
      }
    });
  }, observerOptions);

  headings.forEach((heading) => {
    observer.observe(heading);
  });

  // Handle initial state on load
  // Find the first heading with ID that is in the viewport
  const firstVisibleHeading = Array.from(headings).find((heading) => {
    const rect = heading.getBoundingClientRect();
    return rect.top >= 0 && rect.top <= window.innerHeight;
  });

  if (firstVisibleHeading) {
    const id = firstVisibleHeading.getAttribute("id");
    if (id) {
      activateLink(id);
    }
  }
}

function initMath() {
  // Render all inline math elements
  var mathElements = document.querySelectorAll(".katex-inline");
  mathElements.forEach(function (element) {
    var formula = element.textContent;
    try {
      katex.render(formula, element, {
        throwOnError: false,
        displayMode: false,
      });
    } catch (e) {
      console.error("KaTeX rendering error:", e);
    }
  });

  // Render all block math elements
  var blockMathElements = document.querySelectorAll(".katex-block");
  blockMathElements.forEach(function (element) {
    var formula = element.textContent;
    try {
      katex.render(formula, element, {
        throwOnError: false,
        displayMode: true,
      });
    } catch (e) {
      console.error("KaTeX rendering error:", e);
    }
  });
}

document.addEventListener("DOMContentLoaded", function () {
  initSearch();
  initTheme();
  initToc();
  initMath();

  document.addEventListener("keydown", function (event) {
    if ((event.metaKey || event.ctrlKey) && event.key === "k") {
      event.preventDefault();
      const searchModal = document.getElementById("search-modal");
      if (searchModal) {
        searchModal.checked = !searchModal.checked;
        searchModal.dispatchEvent(new Event("change"));
      }
    }
  });
});
