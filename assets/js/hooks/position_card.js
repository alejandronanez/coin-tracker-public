const PositionCard = {
  mounted() {
    this.updatePrices();
  },

  updated() {
    this.updatePrices();
  },

  updatePrices() {
    const data = {
      currentPrice: this.el.dataset.currentPrice,
      pnlPercent: this.el.dataset.pnlPercent,
      pnlStatus: this.el.dataset.pnlStatus,
      pnlColor: this.el.dataset.pnlColor,
      pnlUsd: this.el.dataset.pnlUsd,
      progressPercent: this.el.dataset.progressPercent,
      progressBarColor: this.el.dataset.progressBarColor,
      progressText: this.el.dataset.progressText
    };

    this.updateElement('[data-role="current-price"]', data.currentPrice, data.pnlColor);
    this.updateElement('[data-role="pnl-percent"]', data.pnlPercent, data.pnlColor);
    this.updateElement('[data-role="pnl-usd"]', data.pnlUsd, data.pnlColor);
    this.updateElement('[data-role="pnl-status"]', data.pnlStatus);
    this.updateElement('[data-role="progress-text"]', data.progressText);

    const progressBar = this.el.querySelector('[data-role="progress-bar"]');
    if (progressBar) {
      progressBar.style.width = `${data.progressPercent}%`;
      progressBar.className = progressBar.className.replace(
        /bg-(green|red|gray)-\d+/g,
        data.progressBarColor
      );
    }
  },

  updateElement(selector, text, colorClass = null) {
    const el = this.el.querySelector(selector);
    if (el) {
      el.textContent = text;
      if (colorClass) {
        el.className = el.className.replace(/text-(green|red|gray)-\d+/g, colorClass);
      }
    }
  }
};

export default PositionCard;
