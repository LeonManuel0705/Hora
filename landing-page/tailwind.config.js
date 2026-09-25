// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

export default {
  content: ['./src/**/*.html', './dist/**/*.html'],
  theme: {
    extend: {
      fontFamily: {
        display: ['"Radio Canada Big"', 'sans-serif'],
        body: ['"Inclusive Sans"', 'sans-serif'],
      },
      colors: {
        brand: {
          purple: '#7353CD',
          pink: '#9580E8',
          blue: '#7E60DB',
          text: '#1D1C24',
          muted: '#575665',
          surface: 'rgba(255,255,255,0.7)',
        }
      },
      backgroundImage: {
        'gradient-brand': 'linear-gradient(135deg, #7353CD 0%, #7E60DB 50%, #9580E8 100%)',
        'gradient-subtle': 'linear-gradient(180deg, #FFFFFF 0%, #FBFAFF 100%)',
      },
      borderRadius: {
        'xl': '1rem',
        '2xl': '1.5rem',
        '3xl': '2rem',
      },
      boxShadow: {
        'glass': '0 8px 32px rgba(115, 83, 205, 0.1)',
        'soft': '0 4px 12px rgba(0, 0, 0, 0.05)',
      }
    }
  },
  plugins: [],
}
