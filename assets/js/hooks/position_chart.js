import { Chart, registerables } from 'chart.js';
import 'chartjs-adapter-date-fns';

Chart.register(...registerables);

const PositionChart = {
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
            label: 'Position',
            data: chartData.data,
            borderColor: '#f59e0b',
            backgroundColor: 'rgba(245, 158, 11, 0.1)',
            borderWidth: 2,
            tension: 0,
            fill: true,
            pointRadius: 2,
            pointHoverRadius: 5,
            stepped: 'before'
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
            reverse: true,
            min: 1,
            max: 11,
            grid: {
              color: 'rgba(55, 65, 81, 0.2)',
              borderDash: [4, 4],
              drawBorder: false
            },
            ticks: {
              color: '#f59e0b',
              stepSize: 1,
              callback: (value) => {
                if (value === 11) return 'Out';
                if (value >= 1 && value <= 10) return '#' + value;
                return '';
              }
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
                const value = context.parsed.y;
                return value === 11 ? 'Position: Out of Top 10' : `Position: #${value}`;
              }
            }
          }
        }
      }
    });
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

export default PositionChart;
