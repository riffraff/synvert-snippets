Synvert::Rewriter.new "use_will_paginate_new_syntax" do
  description <<-EOF
It uses will_paginate new syntax.

    Post.paginate(:conditions => {:active => true}, :order => "created_at DESC", :per_page => 10, :page => 1)
    =>
    Post.where(:active => true).order("created_at DESC").paginate(:per_page => 10, :page => 1)

    Post.paginated_each(:conditions => {:active => true}, :order => "created_at DESC", :per_page => 10) do |post|
    end
    =>
    Post.where(:active => true).order("created_at DESC").find_each(:batch_size => 10) do |post|
    end
  EOF

  if_gem 'will_paginate', {gte: '3.0.0'}

  AR_KEYS = [:conditions, :order, :joins, :select, :from, :having, :group, :include, :limit, :offset, :lock, :readonly]
  WP_KEYS = [:page, :per_page]
  AR_KEYS_CONVERTERS = {
    :conditions => :where,
    :include => :includes
  }

  helper_method :generate_new_queries do |hash_node|
    new_queries = []
    hash_node.children.each do |pair_node|
      if AR_KEYS.include? pair_node.key.to_value
        method = AR_KEYS_CONVERTERS[pair_node.key.to_value] || pair_node.key.to_value
        new_queries << "#{method}(#{strip_brackets(pair_node.value.to_source)})"
      end
    end
    new_queries.join(".")
  end

  helper_method :generate_will_paginate_query do |hash_node|
    wp_params = []
    hash_node.children.each do |pair_node|
      if WP_KEYS.include? pair_node.key.to_value
        wp_params << pair_node.to_source
      end
    end
    if wp_params.length > 0
      "paginate(#{wp_params.join(', ')})"
    else
      "paginate"
    end
  end

  %w(app/**/*.rb lib/**/*.rb).each do |file_pattern|
    within_files file_pattern do
      # Post.paginate(:conditions => {:active => true}, :order => "created_at DESC", :per_page => 10, :page => 1)
      # =>
      # Post.where(:active => true).order("created_at DESC").paginate(:per_page => 10, :page => 1)
      within_node type: 'send', message: 'paginate', arguments: {size: 1} do
        argument_node = node.arguments.last
        if :hash == argument_node.type && (AR_KEYS & argument_node.keys.map(&:to_value)).length > 0
          replace_with add_receiver_if_necessary("#{generate_new_queries(argument_node)}.#{generate_will_paginate_query(argument_node)}")
        end
      end

      # Post.paginated_each(:conditions => {:active => true}, :order => "created_at DESC", :per_page => 10) do |post|
      # end
      # =>
      # Post.where(:active => true).order("created_at DESC").find_each(:batch_size => 10) do |post|
      # end
      within_node type: 'send', message: 'paginated_each', arguments: {size: 1} do
        argument_node = node.arguments.last
        if :hash == argument_node.type
          new_code = []
          if (AR_KEYS & argument_node.keys.map(&:to_value)).length > 0
            new_code << generate_new_queries(argument_node)
          end
          if argument_node.has_key? :per_page
            new_code << "find_each(:batch_size => #{argument_node.hash_value(:per_page).to_source})"
          else
            new_code << "find_each"
          end
          replace_with add_receiver_if_necessary(new_code.join('.'))
        end
      end

      within_node type: 'send', message: 'paginated_each', arguments: {size: 0} do
        replace_with add_receiver_if_necessary('find_each')
      end
    end
  end
end
