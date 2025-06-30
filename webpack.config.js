const path = require('path')
const TerserPlugin = require('terser-webpack-plugin')

module.exports = {
  watch: true,
  watchOptions: {
    aggregateTimeout: 500,
    ignored: /node_modules/
  },
  entry: './src/index.js',
  output: {
    filename: 'application.min.js',
    path: path.resolve(__dirname, 'public', 'js')
  },
  optimization: {
    minimizer: [
      new TerserPlugin({
        parallel: true,
        terserOptions: {
          compress: {
            passes: 2
          },
          mangle: true
        }
      })
    ]
  }
}