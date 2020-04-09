# frozen_string_literal: true

require 'rails_helper'

describe 'variable editing', type: :feature do
  let(:exclusions) { Cluster.variable_handlers }
  let(:fake_data) { Faker::Crypto.sha256 }
  let(:terra) { Terraform }
  let(:instance_terra) { instance_double(Terraform) }

  context 'with sources' do
    let(:variable_names) { collect_variable_names }
    let(:variables) { Variable.new(Source.variables.pluck(:content)) }

    before do
      allow(terra).to receive(:new).and_return(instance_terra)
      allow(instance_terra).to receive(:validate)
      populate_sources
      visit('/variables')
    end

    it 'has a form entry for each variable' do
      (variable_names - exclusions).each do |key|
        expect(page)
          .to have_selector("[name|='variables[#{key}]']")
          .or have_selector("##{key}_new_value")
      end
    end

    it 'stores form data for variables' do
      random_variable_key = nil
      until random_variable_key &&
            variables.type(random_variable_key) == 'string'
        random_variable_key = (variable_names - exclusions).sample
      end
      fill_in("variables[#{random_variable_key}]", with: fake_data)
      click_on('Save')

      expect(KeyValue.get(variables.storage_key(random_variable_key)))
        .to eq(fake_data)
      expect(page).to have_content('Variables were successfully updated.')
    end

    it 'fails to update and shows error' do
      random_variable_key = nil
      until random_variable_key &&
            variables.type(random_variable_key) == 'string'
        random_variable_key = (variable_names - exclusions).sample
      end
      fill_in("variables[#{random_variable_key}]", with: fake_data)
      allow(Variable).to receive(:new).and_return(variables)
      allow(variables).to receive(:save).and_return(false)
      active_model_errors = ActiveModel::Errors.new(variables).tap do |e|
        e.add(:variable, 'is wrong')
      end
      allow(variables).to receive(:errors).and_return(active_model_errors)
      click_on('Save')

      expect(page).not_to have_content('Variables were successfully updated.')
      expect(page).to have_content('Variable is wrong')
    end
  end

  context 'with sources visit plan' do
    let(:variable_names) { collect_variable_names }
    let(:variables) { Variable.new(Source.variables.pluck(:content)) }
    let(:instance_var) { instance_double(Variable) }
    let(:instance_var_controller) { instance_double(VariablesController) }
    let!(:random_path) { random_export_path }
    let(:log_filename) { 'ruby-terraform-test.log' }
    let(:expected_random_log_path) { File.join(random_path, log_filename) }

    before do
      Rails.configuration.x.terraform_log_filename = expected_random_log_path
      FileUtils.mkdir_p(random_path)
      populate_sources(true)
      visit('/variables')
    end

    after do
      FileUtils.rm_rf(random_path)
    end

    it 'stores form data for variables and redirects to plan' do
      allow(Variable).to receive(:load).and_return(variables)
      fill_in('variables[test_password]', with: fake_data)
      find('#next').click
      expect(KeyValue.get(variables.storage_key('test_password')))
        .to eq(fake_data)

      expect(page).not_to have_content('Variables were successfully updated.')
      expect(page).to have_current_path(plan_path)
    end
  end

  it 'notifies that no variables are defined' do
    allow(terra).to receive(:new).and_return(instance_terra)
    allow(instance_terra).to receive(:validate)

    visit('/variables')
    expect(page).to have_content('No variables are defined!')
  end

  it 'shows script error on page' do
    allow(Variable).to receive(:load).and_return(error: 'wrong')
    warning_message = 'Please, edit the scripts'
    visit('/variables')
    expect(page).not_to have_content('No variables are defined!')
    expect(page).to have_content('wrong').and have_content(warning_message)
    expect(page).to have_current_path(sources_path)
  end
end
