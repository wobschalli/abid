require_relative 'components/master'

class Home < Phlex::HTML
  include Components

  def view_template
    Layout do
      p(class: 'text-black dark:text-white') { "you've successfully logged in" }
    end
  end
end
