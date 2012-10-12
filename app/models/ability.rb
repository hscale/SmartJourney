class Ability
  include CanCan::Ability

  def initialize(user)

    Rails.logger.debug( "IN CHECK ABILITY" )

    # if logged in.
    if user
      #reports.
      if user.role?(:super_user)
        can :manage, Report #super users can manage all reports
        can :manage, :planned_incident
      else
        can :manage, Report do |r|
          r.creator.uri == user.uri #can only manage reports reported by themselves
        end
      end
    end

    # not logged in users can create and read reports.
    can [:create, :read], Report


    # Define abilities for the passed in user here. For example:
    #
    #   user ||= User.new # guest user (not logged in)
    #   if user.admin?
    #     can :manage, :all
    #   else
    #     can :read, :all
    #   end
    #
    # The first argument to `can` is the action you are giving the user permission to do.
    # If you pass :manage it will apply to every action. Other common actions here are
    # :read, :create, :update and :destroy.
    #
    # The second argument is the resource the user can perform the action on. If you pass
    # :all it will apply to every resource. Otherwise pass a Ruby class of the resource.
    #
    # The third argument is an optional hash of conditions to further filter the objects.
    # For example, here the user can only update published articles.
    #
    #   can :update, Article, :published => true
    #
    # See the wiki for details: https://github.com/ryanb/cancan/wiki/Defining-Abilities
  end
end
