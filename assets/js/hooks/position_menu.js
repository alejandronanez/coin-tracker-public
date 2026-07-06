const PositionMenu = {
  mounted() {
    this.handleDocumentClick = (event) => {
      if (this.el.open && !this.el.contains(event.target)) {
        this.el.open = false;
      }
    };

    document.addEventListener("click", this.handleDocumentClick);
  },

  beforeUpdate() {
    this.wasOpen = this.el.open;
  },

  updated() {
    if (this.wasOpen) {
      this.el.open = true;
    }
  },

  destroyed() {
    document.removeEventListener("click", this.handleDocumentClick);
  }
};

export default PositionMenu;
