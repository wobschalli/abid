# A root-relative path with the mount prefix applied. The app may live under
# a prefix (abidepurdue.com/ridebot, so the domain root is free for something
# else); Rack sets SCRIPT_NAME from it and Sinatra's url() prepends it. Every
# href/action/endpoint in the views goes through here — a bare "/board" would
# jump out of the prefix the moment it was clicked.
module PathHelper
  def path(target)
    url(target, false)
  end
end

module Components
  extend Phlex::Kit
  include PathHelper

  class Icon < Phlex::SVG
    def initialize(id:'', d:'', klass:'w-6 h-6', clip_rule:'', fill_rule:'', ahid:false, alabel:nil, vbox:'0 0 20 20')
      @id = id
      @d = d
      @klass = klass
      @clip_rule = clip_rule
      @fill_rule = fill_rule
      @ahid = ahid
      @alabel = alabel
      @vbox = vbox
    end

    def view_template
      svg id: @id, aria_hidden: @ahid, aria_label: @alabel, class: @klass, fill: 'currentColor', viewBox: @vbox, xmlns: 'http://www.w3.org/2000/svg' do
        path d: @d, fill_rule: @fill_rule, clip_rule: @clip_rule
      end
    end
  end
end
