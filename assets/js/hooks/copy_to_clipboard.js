// Hook that copies a value to the clipboard when tapped/clicked
// Uses iOS-specific fallback since Clipboard API requires HTTPS on iOS Safari
export default {
  mounted() {
    this.handleClick = (e) => {
      // Don't call preventDefault() - iOS Safari needs the full user gesture chain
      e.stopPropagation();
      this.copyToClipboard();
    };

    // Use 'click' instead of 'pointerdown' - iOS Safari requires 'click' for
    // clipboard operations to be recognized as a trusted user gesture
    this.el.addEventListener("click", this.handleClick);
  },

  destroyed() {
    this.el.removeEventListener("click", this.handleClick);
    if (this.restoreTimeout) {
      clearTimeout(this.restoreTimeout);
    }
  },

  isIOS() {
    return /ipad|iphone/i.test(navigator.userAgent);
  },

  copyToClipboard() {
    const value = this.el.dataset.copyValue;
    if (!value) return;

    // iOS Safari requires HTTPS for Clipboard API, so use fallback directly
    // Also use fallback if Clipboard API is unavailable
    if (this.isIOS() || !navigator.clipboard?.writeText) {
      this.fallbackCopy(value);
      return;
    }

    // Modern Clipboard API for non-iOS browsers
    navigator.clipboard
      .writeText(value)
      .then(() => this.showFeedback())
      .catch(() => this.fallbackCopy(value));
  },

  fallbackCopy(value) {
    const textarea = document.createElement("textarea");
    textarea.value = value;
    textarea.style.position = "fixed";
    textarea.style.left = "-9999px";
    textarea.style.top = "0";
    textarea.style.opacity = "0";
    // iOS Safari requires these attributes for clipboard operations to work
    textarea.contentEditable = true;
    textarea.readOnly = false;
    document.body.appendChild(textarea);

    // iOS requires special selection handling
    if (this.isIOS()) {
      // Must focus before selection for iOS clipboard to work
      textarea.focus();
      const range = document.createRange();
      range.selectNodeContents(textarea);
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      textarea.setSelectionRange(0, 999999);
    } else {
      textarea.focus();
      textarea.select();
    }

    try {
      if (document.execCommand("copy")) {
        this.showFeedback();
      }
    } catch (err) {
      console.error("Fallback copy failed:", err);
    }

    document.body.removeChild(textarea);
  },

  showFeedback() {
    // Clear any pending restoration to handle rapid clicks
    if (this.restoreTimeout) {
      clearTimeout(this.restoreTimeout);
    }

    // Try text-based feedback first (for card-style buttons)
    const feedbackEl = this.el.querySelector("[data-copy-feedback]");
    if (feedbackEl) {
      feedbackEl.classList.remove("opacity-0");
      feedbackEl.classList.add("opacity-100");

      this.restoreTimeout = setTimeout(() => {
        feedbackEl.classList.remove("opacity-100");
        feedbackEl.classList.add("opacity-0");
        this.restoreTimeout = null;
      }, 1500);
      return;
    }

    // Fallback to icon swap (for icon-only buttons)
    const icon = this.el.querySelector("svg");
    if (!icon) return;

    const originalHTML = icon.outerHTML;

    // Replace with checkmark icon
    icon.outerHTML = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="${icon.getAttribute("class")}">
      <path fill-rule="evenodd" d="M16.704 4.153a.75.75 0 0 1 .143 1.052l-8 10.5a.75.75 0 0 1-1.127.075l-4.5-4.5a.75.75 0 0 1 1.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 0 1 1.05-.143Z" clip-rule="evenodd" />
    </svg>`;

    // Restore original icon after delay
    this.restoreTimeout = setTimeout(() => {
      const currentIcon = this.el.querySelector("svg");
      if (currentIcon) {
        currentIcon.outerHTML = originalHTML;
      }
      this.restoreTimeout = null;
    }, 1500);
  },
};
