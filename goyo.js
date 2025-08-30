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
  li.innerHTML = `<a class="border border-gray-500/15 my-2"><div class="prose prose-sm"><h3>${item.item.title}</h3><p>${makeTeaser(item.item.body, terms)}</p></div></a>`;
  li.addEventListener("click", function () {
    window.location.href = item.item.id;
  });
  return li;
}

function initSearch() {
  var $searchInput = document.getElementById("search");
  if (!$searchInput) {
    return;
  }

  var $searchResults = document.querySelector(".search-results");
  var $searchResultsHeader = document.querySelector(".search-results__header");
  var $searchResultsItems = document.querySelector(".search-results__items");
  var MAX_ITEMS = 10;

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

  $searchInput.addEventListener(
    "keyup",
    debounce(function () {
      var term = $searchInput.value.trim();
      if (term === currentTerm || !fuse) {
        return;
      }
      $searchResults.style.display = term === "" ? "none" : "block";
      $searchResultsItems.innerHTML = "";
      if (term === "") {
        return;
      }

      var results = fuse.search(term).filter(function (r) {
        return r.item.body !== "";
      });

      if (results.length === 0) {
        $searchResultsHeader.innerText = `No results for '${term}'`;
        return;
      }

      currentTerm = term;
      $searchResultsHeader.innerText = `${results.length} results for '${term}':`;
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
  if (searchModal) {
    searchModal.addEventListener("change", function () {
      if (this.checked) {
        setTimeout(function () {
          $searchInput.focus();
        }, 100);
      }
    });
  }
}

function initTheme() {
  var themeController = document.querySelector(".theme-controller");
  if (!themeController) {
    return;
  }

  var fallbackTheme =
    window && window.fallbackTheme ? window.fallbackTheme : "night";
  var currentTheme = localStorage.getItem("theme") || fallbackTheme;
  document.documentElement.setAttribute("data-theme", currentTheme);
  themeController.checked = currentTheme === "night";

  themeController.addEventListener("change", function (e) {
    var theme = e.target.checked ? "night" : "lofi";
    document.documentElement.setAttribute("data-theme", theme);
    localStorage.setItem("theme", theme);
  });
}

function initToc() {
  const headings = document.querySelectorAll(
    ".prose h1, .prose h2, .prose h3, .prose h4, .prose h5, .prose h6",
  );
  const tocLinks = document.querySelectorAll(".toc-link");
  const tocDetails = document.querySelectorAll(".toc-details");

  const observerOptions = {
    root: null, // viewport
    rootMargin: "0px 0px -50% 0px", // Trigger when 50% of the element is visible
    threshold: 0, // Trigger as soon as any part of the element is visible
  };

  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      const id = entry.target.getAttribute("id");
      const correspondingLink = document.querySelector(
        `.toc-link[href="#${id}"]`,
      );

      if (entry.isIntersecting) {
        // Remove active class from all links and close all details
        tocLinks.forEach((link) => link.classList.remove("active"));
        tocDetails.forEach((detail) => (detail.open = false));

        // Add active class to the current link
        if (correspondingLink) {
          correspondingLink.classList.add("active");
          let parentDetails = correspondingLink.closest("details");
          while (parentDetails) {
            parentDetails.open = true;
            parentDetails = parentDetails.parentElement.closest("details");
          }
        }
      }
    });
  }, observerOptions);

  headings.forEach((heading) => {
    observer.observe(heading);
  });

  // Handle initial state on load
  // Find the first heading in view and activate its TOC link
  const firstVisibleHeading = Array.from(headings).find((heading) => {
    const rect = heading.getBoundingClientRect();
    return rect.top >= 0 && rect.top <= window.innerHeight;
  });

  if (firstVisibleHeading) {
    const id = firstVisibleHeading.getAttribute("id");
    const correspondingLink = document.querySelector(
      `.toc-link[href="#${id}"]`,
    );
    if (correspondingLink) {
      correspondingLink.classList.add("active");
      let parentDetails = correspondingLink.closest("details");
      while (parentDetails) {
        parentDetails.open = true;
        parentDetails = parentDetails.parentElement.closest("details");
      }
    }
  }
}

document.addEventListener("DOMContentLoaded", function () {
  initSearch();
  initTheme();
  initToc();

  document.addEventListener('keydown', function(event) {
    if ((event.metaKey || event.ctrlKey) && event.key === 'k') {
      event.preventDefault();
      const searchModal = document.getElementById('search-modal');
      if (searchModal) {
        searchModal.checked = !searchModal.checked;
        searchModal.dispatchEvent(new Event('change'));
      }
    }
  });
});
