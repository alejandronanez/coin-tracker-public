// Hook that automatically prepends "-" to input values for stop loss fields
export default {
  mounted() {
    this.handleBlur = () => this.ensureNegative();
    this.el.addEventListener("blur", this.handleBlur);
  },

  destroyed() {
    this.el.removeEventListener("blur", this.handleBlur);
  },

  ensureNegative() {
    let value = this.el.value.trim();
    // Only add negative sign if there's a value and it doesn't already start with "-"
    if (value && !value.startsWith("-")) {
      this.el.value = "-" + value;
    }
  }
};
