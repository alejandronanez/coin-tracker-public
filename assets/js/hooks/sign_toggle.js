// Hook that toggles the sign (+/-) of a numeric input value
export default {
  mounted() {
    this.handlePointerDown = (e) => {
      e.preventDefault();
      this.toggleSign();
    };

    this.el.addEventListener("pointerdown", this.handlePointerDown);
  },

  destroyed() {
    this.el.removeEventListener("pointerdown", this.handlePointerDown);
  },

  toggleSign() {
    const inputId = this.el.dataset.inputId;
    const input = document.getElementById(inputId);
    if (!input) return;

    let value = input.value.trim();
    if (!value) return;

    // Toggle the sign
    if (value.startsWith("-")) {
      input.value = value.substring(1);
    } else {
      input.value = "-" + value;
    }

    // Dispatch input event to trigger phx-change
    input.dispatchEvent(new Event("input", { bubbles: true }));
  }
};
