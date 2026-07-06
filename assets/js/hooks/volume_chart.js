import { Chart, registerables } from 'chart.js';
import 'chartjs-adapter-date-fns';

Chart.register(...registerables);

const VolumeChart = {
  mounted() {
    const chartData = JSON.parse(this.el.dataset.chart);
    const canvas = document.createElement('canvas');
    canvas.style.width = '100%';
    canvas.style.height = '100%';
    this.el.appendChild(canvas);

    this.chart = new Chart(canvas.getContext('2d'), {
      type: 'line',
      data: {
        datasets: [
          {
            label: 'Volume',
            data: chartData.data,
            borderColor: '#10b981',
            backgroundColor: 'rgba(16, 185, 129, 0.1)',
            borderWidth: 2,
            tension: 0.4,
            fill: true,
            pointRadius: 0,
            pointHoverRadius: 4
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: {
          duration: 300
        },
        interaction: {
          mode: 'index',
          intersect: false
        },
        scales: {
          x: {
            type: 'time',
            time: {
              unit: 'hour',
              displayFormats: {
                minute: 'HH:mm',
                hour: 'MMM dd, HH:mm',
                day: 'MMM dd',
                week: 'MMM dd'
              },
              tooltipFormat: 'MMM dd, HH:mm'
            },
            grid: {
              color: 'rgba(55, 65, 81, 0.4)',
              borderDash: [4, 4],
              drawBorder: false
            },
            ticks: {
              color: '#9ca3af'
            },
            border: {
              color: '#374151'
            }
          },
          y: {
            type: 'linear',
            position: 'left',
            grid: {
              color: 'rgba(55, 65, 81, 0.2)',
              borderDash: [4, 4],
              drawBorder: false
            },
            ticks: {
              color: '#10b981',
              callback: (value) => '$' + this.formatVolume(value)
            },
            border: {
              color: '#374151'
            }
          }
        },
        plugins: {
          legend: {
            display: false
          },
          tooltip: {
            backgroundColor: '#1f2937',
            titleColor: '#f3f4f6',
            bodyColor: '#f3f4f6',
            borderColor: '#374151',
            borderWidth: 1,
            callbacks: {
              label: (context) => {
                return `Volume: $${this.formatVolume(context.parsed.y)}`;
              }
            }
          }
        }
      }
    });
  },

  formatVolume(value) {
    if (value === null || value === undefined) return '-';
    if (value >= 1_000_000_000) return (value / 1_000_000_000).toFixed(2) + 'B';
    if (value >= 1_000_000) return (value / 1_000_000).toFixed(2) + 'M';
    if (value >= 1_000) return (value / 1_000).toFixed(2) + 'K';
    return value.toFixed(2);
  },

  updated() {
    const chartData = JSON.parse(this.el.dataset.chart);
    this.chart.data.datasets[0].data = chartData.data;
    this.chart.update('none');
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy();
    }
  }
};

export default VolumeChart;
