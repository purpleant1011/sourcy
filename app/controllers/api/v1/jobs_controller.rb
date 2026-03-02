module Api
  module V1
    class JobsController < BaseController
      def show
        extraction = ExtractionRun.joins(:source_product).where(id: params[:id], source_products: { account_id: Current.account.id }).first
        translation = TranslationRun.joins(extraction_run: :source_product)
          .where(id: params[:id], source_products: { account_id: Current.account.id }).first

        run = extraction || translation
        return render_error(code: "RESOURCE_NOT_FOUND", message: "Job not found", status: :not_found) if run.blank?

        render_success(
          data: {
            id: run.id,
            type: run.class.name,
            status: run.status,
            error_message: run.try(:error_message),
            created_at: run.created_at,
            updated_at: run.updated_at
          }
        )
      end
    end
  end
end
