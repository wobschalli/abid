require_relative 'components/master'

class Root < Phlex::HTML
  include Components
  def view_template
    Layout do
      div class: 'h-screen justify-self-center' do
        h1(class: 'text-3xl dark:text-gray-400') { 'Login' }
        Form action: '/' do |f|
          f.labeled_input name: 'username' do
            f.text_input name: 'username', icon_d: 'M10 0a10 10 0 1 0 10 10A10.011 10.011 0 0 0 10 0Zm0 5a3 3 0 1 1 0 6 3 3 0 0 1 0-6Zm0 13a8.949 8.949 0 0 1-4.951-1.488A3.987 3.987 0 0 1 9 13h2a3.987 3.987 0 0 1 3.951 3.512A8.949 8.949 0 0 1 10 18Z'
          end
        end
      end
    end
  end
end
