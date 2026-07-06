import { Chart, registerables } from 'chart.js';
import 'chartjs-adapter-date-fns';

// Register all Chart.js components
Chart.register(...registerables);

const ChartJsChart = {
  mounted() {
    const chartData = JSON.parse(this.el.dataset.chart);
    const canvas = document.createElement('canvas');
    canvas.style.width = '100%';
    canvas.style.height = '100%';
    this.el.appendChild(canvas);

    this.chart = new Chart(canvas.getContext('2d'), {
      type: 'line',
      data: {
        datasets: [{
          label: chartData.series[0].name,
          data: chartData.series[0].data,
          borderColor: '#2563eb',
          backgroundColor: 'rgba(37, 99, 235, 0.1)',
          borderWidth: 2,
          tension: 0.4,
          fill: false,
          pointRadius: 0,
          pointHoverRadius: 4
        }]
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
              unit: 'minute',
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
            min: 0,
            max: 10,
            grid: {
              color: 'rgba(55, 65, 81, 0.4)',
              borderDash: [4, 4],
              drawBorder: false
            },
            ticks: {
              color: '#9ca3af',
              stepSize: 1,
              callback: (value) => Math.floor(value)
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
            borderWidth: 1
          }
        }
      }
    });
  },

  updated() {
    const chartData = JSON.parse(this.el.dataset.chart);

    // Update the dataset with new data
    this.chart.data.datasets[0].data = chartData.series[0].data;

    // Use 'none' animation mode for real-time updates to prevent jank
    this.chart.update('none');
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy();
    }
  }
};

export default ChartJsChart;
