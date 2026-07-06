const BinanceTicker = {
  mounted() {
    this.loadWidget();
  },

  loadWidget() {
    // Check if script already loaded
    if (window.binanceWidgetLoaded) {
      return;
    }

    const script = document.createElement('script');
    script.src = 'https://public.bnbstatic.com/unpkg/growth-widget/cryptoCurrencyWidget@0.0.22.min.js';
    script.async = true;
    script.onload = () => {
      window.binanceWidgetLoaded = true;
    };
    document.head.appendChild(script);
  },

  destroyed() {
    // Clean up if needed
  }
};

export default BinanceTicker;
