const LocalTime = {
  mounted() {
    this.updateTime();
  },

  updated() {
    this.updateTime();
  },

  updateTime() {
    const datetime = this.el.dataset.datetime;
    const format = this.el.dataset.format || 'datetime';

    if (!datetime) {
      console.warn('LocalTime hook: no datetime attribute found');
      return;
    }

    try {
      const date = new Date(datetime);

      if (isNaN(date.getTime())) {
        console.warn('LocalTime hook: invalid datetime', datetime);
        return;
      }

      let formatted;
      const options = this.getFormatOptions(format);

      formatted = new Intl.DateTimeFormat(undefined, options).format(date);

      this.el.textContent = formatted;
    } catch (error) {
      console.error('LocalTime hook error:', error);
      this.el.textContent = datetime;
    }
  },

  getFormatOptions(format) {
    switch (format) {
      case 'date':
        return {
          month: 'short',
          day: 'numeric',
          year: 'numeric'
        };
      case 'time':
        return {
          hour: 'numeric',
          minute: '2-digit',
          hour12: true
        };
      case 'time-24':
        return {
          hour: '2-digit',
          minute: '2-digit',
          hour12: false
        };
      case 'datetime':
        return {
          month: 'short',
          day: 'numeric',
          year: 'numeric',
          hour: 'numeric',
          minute: '2-digit',
          hour12: true
        };
      case 'datetime-short':
        return {
          month: 'short',
          day: 'numeric',
          hour: 'numeric',
          minute: '2-digit',
          hour12: true
        };
      default:
        return {
          month: 'short',
          day: 'numeric',
          year: 'numeric',
          hour: 'numeric',
          minute: '2-digit',
          hour12: true
        };
    }
  }
};

export default LocalTime;
