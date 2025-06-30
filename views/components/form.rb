require_relative 'components'

class Components::Form < Phlex::HTML
  def initialize(action:, method:'post', button_text:'Submit')
    @action = action
    @method = method
    @button_text = button_text
  end

  def view_template(&)
    form action: @action, method: @method do
      div class: 'grid-cols-12 gap-4 p-4' do
        yield
      end

      div class: 'p-4' do
        button(class: 'btn-primary') { @button_text }
      end
    end
  end

  def labeled_input(text:nil, name:, &)
    label(for: "input-group-#{name.dasherize}", class: 'block mb-2 text-sm font-medium text-gray-900 dark:text-white') { text ? text : name }
    yield
  end

  def text_input(icon_d:nil, name:, placeholder:nil)
    div class: 'flex' do
      if icon_d
        div class: 'inline-flex items-center px-3 text-sm text-gray-900 bg-gray-200 border rounded-e-0 border-gray-300 border-e-0 rounded-s-md dark:bg-gray-600 dark:text-gray-400 dark:border-gray-600' do
          render Icon.new(icon_d)
        end
      end
      input name: name, type: 'text', id: "input-group-#{name.dasherize}", class: 'rounded-none rounded-e-lg bg-gray-50 border text-gray-900 focus:ring-blue-500 focus:border-blue-500 block flex-1 min-w-0 w-full text-sm border-gray-300 p-2.5  dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500', placeholder: placeholder
    end
  end

  private
  class Icon < Phlex::SVG
    def initialize(ds)
      @ds = ds
    end

    def view_template
      svg class: 'w-4 h-4 text-gray-500 dark:text-gray-400', aria_hidden: 'true', xmlns: 'http://www.w3.org/2000/svg', fill: 'currentColor', viewBox: '0 0 20 16' do
        (@ds.is_a?(Array) ? @ds : [ @ds ]).each do |d|
          path d: d
        end
      end
    end
  end
end
