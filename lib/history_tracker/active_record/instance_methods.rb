module HistoryTracker
  module ActiveRecord
    module InstanceMethods

      def association_chain
        traverse_association_chain(self)
      end

      def history_tracks
        @history_tracks ||= history_tracker_class.where(association_hash_query)
      end

      # Write history track manually
      #
      # @params action
      # @params changes
      # @params modifier_id
      #
      # Returns the track that has written
      def write_history_track!(action, changes={}, modifier_id=HistoryTracker.current_modifier_id)
        changes = modified_attributes_for_destroy if action.to_sym == :destroy

        original, modified = transform_changes(changes)
        tracked_attributes = default_history_tracker_attributes(action, modifier_id)
        tracked_attributes[:original] = (action == :create) ? {} : original
        tracked_attributes[:modified] = (action == :destroy) ? {} : modified
        tracked_attributes[:changes]  = (action == :destroy) ? {} : changes

        clear_trackable_memoization
        history_tracker_class.create!(tracked_attributes)
      end
      alias_method :create_history_track!, :write_history_track!

      # Retrieve the changes attributes
      # By default, it invokes `#changes`, otherwise it invokes `changes_method` option.
      def history_trackable_changes
        send(history_trackable_options[:changes_method]).stringify_keys
      end

      def without_tracking(method = nil)
        tracking_was_enabled = self.class.tracking_enabled?
        self.class.disable_tracking
        method ? method.to_proc.call(self) : yield
      ensure
        self.class.enable_tracking if tracking_was_enabled
      end

      protected

        def track_history_for_action?(action)
          track_history? && !(action.to_sym == :update && modified_attributes_for_update.blank?)
        end

      private

        def traverse_association_chain(node = self)
          list = node.history_trackable_parent ? traverse_association_chain(node.history_trackable_parent) : []
          list << association_hash(node)
          list
        end

        def association_hash(node = self)
          if node.history_trackable_parent
            meta = node.history_trackable_parent.class.reflections.values.select do |relation|
              relation.name == node.history_trackable_options[:inverse_of] &&
              relation.class_name == node.class.name
            end.first
          end

          # if root node has no meta, and should use class name instead
          name = meta ? meta.name.to_s : node.class.name

          ActiveSupport::OrderedHash['name', name, 'id', node.id]
        end

        def association_hash_query
          query = association_hash.inject({}) do |h, (k, v)|
            h["association_chain.#{k}"] = v
            h
          end
        end

        # Retrieves the modified attributes for create action
        #
        # Returns hash which contains field as key and [nil, value] as value
        # Eg: {"name"=>[nil, "Listing 1"], "description"=> [nil, "Description 1"]}
        def modified_attributes_for_create
          @modified_attributes_for_create ||= attributes.inject({}) do |h, (k, v)|
            h[k] = [nil, v]
            h
          end.merge(history_trackable_changes).select { |k, v| self.class.tracked_field?(k, :create) && (v[0] != v[1]) }
        end

        # Retrieves the modified attributes for update action
        #
        # Returns hash which contains field as key and [old_value, new_value] as value
        # Eg: {"name"=>["Old Listing", "Listing 1"], "description"=> ["Old Description", "Description 1"]}
        def modified_attributes_for_update
          @modified_attributes_for_update ||= history_trackable_changes.select { |k, _| self.class.tracked_field?(k, :update) }
        end

        # Retrieves the modified attributes for destroy action
        #
        # Returns hash which contains field as key and [value, nil] as value
        # Eg: {"name"=>["Listing 1", nil], "description"=> ["Description 1", nil]}
        def modified_attributes_for_destroy
          @modified_attributes_for_destroy ||= attributes.inject({}) do |h, (k, v)|
            h[k] = [v, nil]
            h
          end.merge(history_trackable_changes).select { |k, v| self.class.tracked_field?(k, :destroy) && (v[0] != v[1]) }
        end

        # Returns a Hash of field name to pairs of original and modified values
        # for each tracked field for a given action.
        #
        # @param [ String | Symbol ] action The modification action (:create, :update, :destroy)
        #
        # @return [ Hash<String, Array<Object>> ] the pairs of original and modified
        #   values for each field
        def modified_attributes_for_action(action)
          case action.to_sym
          when :create then modified_attributes_for_create
          when :destroy then modified_attributes_for_destroy
          else modified_attributes_for_update
          end
        end

        # Attributes for history tracker model
        #
        # Returns hash of attributes before saved to tracker model
        def history_tracker_attributes(action)
          return @history_tracker_attributes if @history_tracker_attributes

          @history_tracker_attributes = default_history_tracker_attributes(action)

          changes            = modified_attributes_for_action(action)
          original, modified = transform_changes(changes)
          @history_tracker_attributes[:original] = (action == :create) ? {} : original
          @history_tracker_attributes[:modified] = (action == :destroy) ? {} : modified
          @history_tracker_attributes[:changes]  = (action == :destroy) ? {} : changes
          @history_tracker_attributes
        end

        def default_history_tracker_attributes(action, modifier_id=HistoryTracker.current_modifier_id)
          if modifier_id.class.name == 'Integer'
            {
              association_chain: traverse_association_chain,
              trackable_klass_name: self.class.name,
              modifier_id: modifier_id,
              action: action.to_s
            }
          else
            {
              association_chain: traverse_association_chain,
              trackable_klass_name: self.class.name,
              modifier_mongo_id: modifier_id.to_s,
              modifier_id: 0,
              action: action.to_s
            }
          end
        end

        # Returns an array of original and modified from changes
        #
        def transform_changes(changes)
          original = {}
          modified = {}
          changes.each_pair do |k, v|
            o, m = v
            original[k] = o unless o.nil?
            modified[k] = m unless m.nil?
          end

          [original, modified]
        end

        def track_history_for_action(action)
          if track_history_for_action?(action)
            history_tracker_class.create!(history_tracker_attributes(action.to_sym))
          end
          clear_trackable_memoization
        end

        def track_create
          track_history_for_action(:create)
        end

        def track_update
          track_history_for_action(:update)
        end

        def track_destroy
          track_history_for_action(:destroy)
        end

        def clear_trackable_memoization
          @history_tracker_attributes      = nil
          @modified_attributes_for_create  = nil
          @modified_attributes_for_update  = nil
          @modified_attributes_for_destroy = nil
          @history_tracks                  = nil
        end
    end
  end
end
